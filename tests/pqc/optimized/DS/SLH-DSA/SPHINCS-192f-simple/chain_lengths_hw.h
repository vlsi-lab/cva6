/*
 * chain_lengths_hw.h - native HASH-IP (RV64) WOTS+ chain-length helpers
 *
 * Replaces the HORCRUX-era version that targeted opcode 0x6b/0x3b.
 * All HW access goes through the inline wrappers in inc/hash_ip.h, which
 * use the new opcode-0x5b 64-bit ISA.  Loads use the dual-lane LOAD2
 * (cus_load2) so two 64-bit lanes are written per coprocessor issue cycle,
 * halving the load count vs. single-lane cus_load.
 */

#ifndef CHAIN_LENGTHS_HW_H
#define CHAIN_LENGTHS_HW_H

#include <stdint.h>
#include "../../../../../inc/hash_ip.h"

/* Pack 8 little-endian bytes into a uint64_t lane. */
static inline uint64_t cl_pack_u64_le(const uint8_t *p) {
    return  (uint64_t)p[0]
         | ((uint64_t)p[1] <<  8)
         | ((uint64_t)p[2] << 16)
         | ((uint64_t)p[3] << 24)
         | ((uint64_t)p[4] << 32)
         | ((uint64_t)p[5] << 40)
         | ((uint64_t)p[6] << 48)
         | ((uint64_t)p[7] << 56);
}

/* Helper: unpack one 32-bit word into 8 MSB-first nibbles. */
static inline void cl_unpack_word(uint8_t *dst, uint32_t w) {
    dst[0] =  w >> 28;        dst[1] = (w >> 24) & 0xF;
    dst[2] = (w >> 20) & 0xF; dst[3] = (w >> 16) & 0xF;
    dst[4] = (w >> 12) & 0xF; dst[5] = (w >>  8) & 0xF;
    dst[6] = (w >>  4) & 0xF; dst[7] =  w        & 0xF;
}

/* 128f: 16 input bytes -> 32 nibbles + 3 checksum nibbles (35 total).
 * 1 dual-lane LOAD2 covers lanes 0,1 (16 bytes). */
static inline void chain_lengths_hw_128f(uint8_t *lengths, const uint8_t *msg) {
    cus_load2(cl_pack_u64_le(msg), cl_pack_u64_le(msg + 8), 0);
    __asm__ volatile ("fence" ::: "memory");
    hash_cl_128f();

    uint32_t w[5];
    for (int i = 0; i < 5; i++) w[i] = cus_store(i);
    for (int i = 0; i < 4; i++) cl_unpack_word(&lengths[i * 8], w[i]);
    /* Last 3 nibbles of word 4 are the checksum. */
    lengths[32] =  w[4] >> 28;
    lengths[33] = (w[4] >> 24) & 0xF;
    lengths[34] = (w[4] >> 20) & 0xF;
}

/* 192f: 24 input bytes -> 48 nibbles + 3 checksum nibbles (51 total).
 * 1 LOAD2 for lanes 0,1 + 1 single LOAD for lane 2 (3 lanes total). */
static inline void chain_lengths_hw_192f(uint8_t *lengths, const uint8_t *msg) {
    cus_load2(cl_pack_u64_le(msg), cl_pack_u64_le(msg + 8), 0);
    cus_load64(cl_pack_u64_le(msg + 16), 2);
    __asm__ volatile ("fence" ::: "memory");
    hash_cl_192f();

    uint32_t w[7];
    for (int i = 0; i < 7; i++) w[i] = cus_store(i);
    for (int i = 0; i < 6; i++) cl_unpack_word(&lengths[i * 8], w[i]);
    lengths[48] =  w[6] >> 28;
    lengths[49] = (w[6] >> 24) & 0xF;
    lengths[50] = (w[6] >> 20) & 0xF;
}

/* 256f: 32 input bytes -> 64 nibbles + 3 checksum nibbles (67 total).
 * 2 LOAD2 for lanes 0,1 and 2,3 (4 lanes total). */
static inline void chain_lengths_hw_256f(uint8_t *lengths, const uint8_t *msg) {
    cus_load2(cl_pack_u64_le(msg),      cl_pack_u64_le(msg + 8),  0);
    cus_load2(cl_pack_u64_le(msg + 16), cl_pack_u64_le(msg + 24), 2);
    __asm__ volatile ("fence" ::: "memory");
    hash_cl_256f();

    uint32_t w[9];
    for (int i = 0; i < 9; i++) w[i] = cus_store(i);
    for (int i = 0; i < 8; i++) cl_unpack_word(&lengths[i * 8], w[i]);
    lengths[64] =  w[8] >> 28;
    lengths[65] = (w[8] >> 24) & 0xF;
    lengths[66] = (w[8] >> 20) & 0xF;
}

#endif /* CHAIN_LENGTHS_HW_H */
