// AES-128 forward-encrypt-only Accelerator IP -- software driver
// Mirrors tests/keccak64/keccak_axi.c's raw-MMIO-pointer, poll-based style
// (no custom instructions, plain loads/stores to aes_axi_top's registers).
//
// AES_BASE_ADDR here MUST be kept in sync with
// corev_apu/tb/ariane_soc_pkg.sv's AesBase by hand -- same caveat keccak_axi.c
// already has for KECCAK_BASE_ADDR vs. KeccakBase.
//
// Word packing: each 128-bit KEY/BLOCK/RESULT value is two 64-bit words,
// word 0 = bytes[0:7] big-endian (MSB-first), word 1 = bytes[8:15]
// big-endian -- see aes.hjson's header comment for why (matches
// aes_enc128_core's own [127:0] convention with no extra swapping).

#ifndef _AES_HAL_H_
#define _AES_HAL_H_

#include <stdint.h>
#include "aes_axi.h"

#define AES_BASE_ADDR 0x60000000

static inline uint64_t _aes_load_be64(const uint8_t *p)
{
    return ((uint64_t) p[0] << 56) | ((uint64_t) p[1] << 48) |
           ((uint64_t) p[2] << 40) | ((uint64_t) p[3] << 32) |
           ((uint64_t) p[4] << 24) | ((uint64_t) p[5] << 16) |
           ((uint64_t) p[6] << 8)  | ((uint64_t) p[7]);
}

static inline void _aes_store_be64(uint8_t *p, uint64_t v)
{
    p[0] = (uint8_t) (v >> 56); p[1] = (uint8_t) (v >> 48);
    p[2] = (uint8_t) (v >> 40); p[3] = (uint8_t) (v >> 32);
    p[4] = (uint8_t) (v >> 24); p[5] = (uint8_t) (v >> 16);
    p[6] = (uint8_t) (v >> 8);  p[7] = (uint8_t) v;
}

// RESULT reads immediately after the STATUS poll loop confirms READY were
// empirically observed to sometimes return a stale value that stays
// CONSISTENT across several consecutive reads before flipping to the
// correct one (confirmed via debug tracing: a single-shot call needed 1
// extra read to settle, a CTR-chained call's stale value was still stable
// across 3 back-to-back reads and only became correct on the 4th/5th) --
// so a "stop on two matching reads" debounce is fooled by the stuck value
// and returns too early. Unconditionally discarding a generous, fixed
// number of reads before trusting the result works around it regardless
// of how deep the staleness runs in a given context.
#define AES_RESULT_READ_MARGIN 8
static inline uint64_t _aes_read_stable(volatile uint64_t *reg)
{
    int i;
    uint64_t v = *reg;
    for (i = 0; i < AES_RESULT_READ_MARGIN; i++) v = *reg;
    return v;
}

static inline void _aes_read_result(volatile uint64_t *resregs, uint8_t out[16])
{
    _aes_store_be64(out, _aes_read_stable(&resregs[0]));
    _aes_store_be64(out + 8, _aes_read_stable(&resregs[1]));
}

static inline void aes128_set_key_hw(const uint8_t key[16])
{
    volatile uint64_t *keyregs = (volatile uint64_t *) (AES_BASE_ADDR + AES_KEY_0_REG_OFFSET);
    volatile uint64_t *ctrl    = (volatile uint64_t *) (AES_BASE_ADDR + AES_CTRL_REG_OFFSET);
    volatile uint64_t *status  = (volatile uint64_t *) (AES_BASE_ADDR + AES_STATUS_REG_OFFSET);

    keyregs[0] = _aes_load_be64(key);
    keyregs[1] = _aes_load_be64(key + 8);

    *ctrl |= (1ULL << AES_CTRL_INIT_BIT);
    while (((*status) & (1ULL << AES_STATUS_READY_BIT)) == 0) { }
    *ctrl &= ~(1ULL << AES_CTRL_INIT_BIT);
}

static inline void aes128_encrypt_block_hw(const uint8_t in[16], uint8_t out[16])
{
    volatile uint64_t *blkregs = (volatile uint64_t *) (AES_BASE_ADDR + AES_BLOCK_0_REG_OFFSET);
    volatile uint64_t *resregs = (volatile uint64_t *) (AES_BASE_ADDR + AES_RESULT_0_REG_OFFSET);
    volatile uint64_t *ctrl    = (volatile uint64_t *) (AES_BASE_ADDR + AES_CTRL_REG_OFFSET);
    volatile uint64_t *status  = (volatile uint64_t *) (AES_BASE_ADDR + AES_STATUS_REG_OFFSET);

    blkregs[0] = _aes_load_be64(in);
    blkregs[1] = _aes_load_be64(in + 8);

    *ctrl |= (1ULL << AES_CTRL_NEXT_BIT);
    while (((*status) & (1ULL << AES_STATUS_READY_BIT)) == 0) { }

    _aes_read_result(resregs, out);

    *ctrl &= ~(1ULL << AES_CTRL_NEXT_BIT);
}

// === CTR-mode chain: _ctr_start writes BLOCK (like
//     aes128_encrypt_block_hw()) but ALSO sets CTR_INC, so BLOCK's
//     bytes[0:3] are already auto-incremented (32-bit little-endian +1,
//     matching FAEST's aes_increment_iv()) by the time it completes -- the
//     first call in a chain must use this, not the plain
//     aes128_encrypt_block_hw() above, or the chain is off by one. _ctr_next
//     then chains off that with no BLOCK write at all, just pulse
//     NEXT+CTR_INC and read the result.

static inline void aes128_encrypt_block_hw_ctr_start(const uint8_t in[16], uint8_t out[16])
{
    volatile uint64_t *blkregs = (volatile uint64_t *) (AES_BASE_ADDR + AES_BLOCK_0_REG_OFFSET);
    volatile uint64_t *resregs = (volatile uint64_t *) (AES_BASE_ADDR + AES_RESULT_0_REG_OFFSET);
    volatile uint64_t *ctrl    = (volatile uint64_t *) (AES_BASE_ADDR + AES_CTRL_REG_OFFSET);
    volatile uint64_t *status  = (volatile uint64_t *) (AES_BASE_ADDR + AES_STATUS_REG_OFFSET);

    blkregs[0] = _aes_load_be64(in);
    blkregs[1] = _aes_load_be64(in + 8);

    *ctrl |= (1ULL << AES_CTRL_NEXT_BIT) | (1ULL << AES_CTRL_CTR_INC_BIT);
    while (((*status) & (1ULL << AES_STATUS_READY_BIT)) == 0) { }

    _aes_read_result(resregs, out);

    *ctrl &= ~((1ULL << AES_CTRL_NEXT_BIT) | (1ULL << AES_CTRL_CTR_INC_BIT));
}

static inline void aes128_encrypt_block_ctr_next_hw(uint8_t out[16])
{
    volatile uint64_t *resregs = (volatile uint64_t *) (AES_BASE_ADDR + AES_RESULT_0_REG_OFFSET);
    volatile uint64_t *ctrl    = (volatile uint64_t *) (AES_BASE_ADDR + AES_CTRL_REG_OFFSET);
    volatile uint64_t *status  = (volatile uint64_t *) (AES_BASE_ADDR + AES_STATUS_REG_OFFSET);

    *ctrl |= (1ULL << AES_CTRL_NEXT_BIT) | (1ULL << AES_CTRL_CTR_INC_BIT);
    while (((*status) & (1ULL << AES_STATUS_READY_BIT)) == 0) { }

    _aes_read_result(resregs, out);

    *ctrl &= ~((1ULL << AES_CTRL_NEXT_BIT) | (1ULL << AES_CTRL_CTR_INC_BIT));
}

// === aes128_ctr_blocks_hw(): encrypt `nblocks` consecutive CTR-mode blocks
//     starting at `iv` (iv[0:3] treated as a little-endian counter,
//     iv[4:15] fixed -- FAEST's generic_prg() convention). Only the first
//     block's BLOCK write actually happens; the rest chain via CTR
//     auto-increment with no BLOCK write at all.

static inline void aes128_ctr_blocks_hw(const uint8_t iv[16], uint8_t *out, unsigned nblocks)
{
    unsigned i;
    if (nblocks == 0) return;
    aes128_encrypt_block_hw_ctr_start(iv, out);
    for (i = 1; i < nblocks; i++) {
        aes128_encrypt_block_ctr_next_hw(out + 16 * i);
    }
}

// _AES_HAL_H_
#endif
