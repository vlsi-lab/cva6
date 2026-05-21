#include <stdint.h>
#include <string.h>

#include "thash.h"
#include "address.h"
#include "params.h"
#include "utils.h"

#include "fips202.h"

/* ========================================================================
 * Hardware instruction intrinsics (from keccak_coproc.S)
 * ======================================================================== */

extern void cus_load(uint32_t lo, uint32_t hi, uint32_t index);

/* Fused dual-lane load: one OP_LOAD2 instead of two cus_load (halves cycles). */
extern void cus_load2_pair(uint32_t lo_lo, uint32_t lo_hi,
                           uint32_t hi_lo, uint32_t hi_hi,
                           uint32_t idx32);
extern uint32_t cus_store(uint32_t index);

/* 192-level simple thash: single Keccak permutation, no bitmask */
extern void thash1_192_simple_hw_compute(void);
extern void thash2_192_simple_hw_compute(void);

/* ========================================================================
 * Helper functions
 * ======================================================================== */

static uint32_t load32(const uint8_t *x) {
    return (uint32_t)x[0] | ((uint32_t)x[1] << 8) |
           ((uint32_t)x[2] << 16) | ((uint32_t)x[3] << 24);
}

static void store32(uint8_t *x, uint32_t v) {
    x[0] = (uint8_t)(v);
    x[1] = (uint8_t)(v >> 8);
    x[2] = (uint8_t)(v >> 16);
    x[3] = (uint8_t)(v >> 24);
}

/**
 * Takes an array of inblocks concatenated arrays of SPX_N bytes.
 * Uses HW acceleration for 1-block and 2-block cases (simple thash at 192-level).
 */
void thash(unsigned char *out, const unsigned char *in, unsigned int inblocks,
           const spx_ctx *ctx, uint32_t addr[8])
{
    uint32_t i;
    const uint8_t *addr_bytes = (const uint8_t *)addr;

    if (inblocks == 1) {
        /* Load pub_seed to reg[0:5] (24 bytes = 6 words) */
        /* Lanes 0..0+2 (16 bytes) - 1 fused LOAD2. */
            cus_load2_pair(load32(ctx->pub_seed + 0), load32(ctx->pub_seed + 4),
                           load32(ctx->pub_seed + 8), load32(ctx->pub_seed + 12), 0);
        /* Lane 4 (8 bytes) - 1 single load (odd remainder). */
        cus_load(load32(ctx->pub_seed + 16), load32(ctx->pub_seed + 20), 4);

        /* Load addr to reg[6:13] (32 bytes = 8 words) */
        for (i = 0; i < 8; i += 4) {
            cus_load2_pair(load32(addr_bytes + 4*i), load32(addr_bytes + 4*(i+1)),
                           load32(addr_bytes + 4*(i+2)), load32(addr_bytes + 4*(i+3)), 6 + i);
        }

        /* Load input to reg[14:19] (24 bytes = 6 words) */
        /* Lanes 14..15 (16 bytes) - 1 fused LOAD2. */
            cus_load2_pair(load32(in + 0), load32(in + 4),
                           load32(in + 8), load32(in + 12), 14);
        /* Lane 16 (8 bytes) - 1 single load (odd remainder). */
        cus_load(load32(in + 16), load32(in + 20), 18);

        __asm__ volatile("fence" ::: "memory");
        thash1_192_simple_hw_compute();

        for (i = 0; i < 6; i++) {
            uint32_t w = cus_store(i);
            store32(out + 4*i, w);
        }
        return;
    }

    if (inblocks == 2) {
        /* Load pub_seed to reg[0:5] (24 bytes = 6 words) */
        /* Lanes 0..0+2 (16 bytes) - 1 fused LOAD2. */
            cus_load2_pair(load32(ctx->pub_seed + 0), load32(ctx->pub_seed + 4),
                           load32(ctx->pub_seed + 8), load32(ctx->pub_seed + 12), 0);
        /* Lane 4 (8 bytes) - 1 single load (odd remainder). */
        cus_load(load32(ctx->pub_seed + 16), load32(ctx->pub_seed + 20), 4);

        /* Load addr to reg[6:13] (32 bytes = 8 words) */
        for (i = 0; i < 8; i += 4) {
            cus_load2_pair(load32(addr_bytes + 4*i), load32(addr_bytes + 4*(i+1)),
                           load32(addr_bytes + 4*(i+2)), load32(addr_bytes + 4*(i+3)), 6 + i);
        }

        /* Load input to reg[14:25] (48 bytes = 12 words) */
        for (i = 0; i < 12; i += 4) {
            cus_load2_pair(load32(in + 4*i), load32(in + 4*(i+1)),
                           load32(in + 4*(i+2)), load32(in + 4*(i+3)), 14 + i);
        }

        __asm__ volatile("fence" ::: "memory");
        thash2_192_simple_hw_compute();

        for (i = 0; i < 6; i++) {
            uint32_t w = cus_store(i);
            store32(out + 4*i, w);
        }
        return;
    }

    /* Fallback to SW SHAKE256 for inblocks > 2 */
    {
        SPX_VLA(uint8_t, buf, SPX_N + SPX_ADDR_BYTES + inblocks*SPX_N);

        memcpy(buf, ctx->pub_seed, SPX_N);
        memcpy(buf + SPX_N, addr, SPX_ADDR_BYTES);
        memcpy(buf + SPX_N + SPX_ADDR_BYTES, in, inblocks * SPX_N);

        shake256(out, SPX_N, buf, SPX_N + SPX_ADDR_BYTES + inblocks*SPX_N);
    }
}
