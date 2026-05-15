/*
 * chain_lengths_hw.h - native HASH-IP (RV64) WOTS+ chain-length helpers
 *
 * Replaces the HORCRUX-era version that targeted opcode 0x6b/0x3b.
 * All HW access goes through the inline wrappers in inc/hash_ip.h, which
 * use the new opcode-0x5b 64-bit ISA.  The HW IP exposes 9 result regs
 * (result_regs_o[0:8][31:0]) reachable through OP_STORE while CL mode is
 * active, identical in semantics to the legacy 32-bit STORE.
 */

#ifndef CHAIN_LENGTHS_HW_H
#define CHAIN_LENGTHS_HW_H

#include <stdint.h>
#include "../inc/hash_ip.h"

typedef enum {
    CL_128F = 0,
    CL_192F = 1,
    CL_256F = 2
} cl_variant_t;

/* Helper: unpack one 32-bit word into 8 MSB-first nibbles. */
static inline void cl_unpack_word(uint8_t *dst, uint32_t w) {
    dst[0] =  w >> 28;        dst[1] = (w >> 24) & 0xF;
    dst[2] = (w >> 20) & 0xF; dst[3] = (w >> 16) & 0xF;
    dst[4] = (w >> 12) & 0xF; dst[5] = (w >>  8) & 0xF;
    dst[6] = (w >>  4) & 0xF; dst[7] =  w        & 0xF;
}

/* 128f: 16 input bytes -> 32 nibbles + 3 checksum nibbles (35 total). */
static inline void chain_lengths_hw_128f(uint8_t *lengths, const uint32_t *msg32) {
    cus_load(msg32[0], msg32[1], 0);
    cus_load(msg32[2], msg32[3], 2);
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

/* 192f: 24 input bytes -> 48 nibbles + 3 checksum nibbles (51 total). */
static inline void chain_lengths_hw_192f(uint8_t *lengths, const uint32_t *msg32) {
    cus_load(msg32[0], msg32[1], 0);
    cus_load(msg32[2], msg32[3], 2);
    cus_load(msg32[4], msg32[5], 4);
    __asm__ volatile ("fence" ::: "memory");
    hash_cl_192f();

    uint32_t w[7];
    for (int i = 0; i < 7; i++) w[i] = cus_store(i);
    for (int i = 0; i < 6; i++) cl_unpack_word(&lengths[i * 8], w[i]);
    lengths[48] =  w[6] >> 28;
    lengths[49] = (w[6] >> 24) & 0xF;
    lengths[50] = (w[6] >> 20) & 0xF;
}

/* 256f: 32 input bytes -> 64 nibbles + 3 checksum nibbles (67 total). */
static inline void chain_lengths_hw_256f(uint8_t *lengths, const uint32_t *msg32) {
    cus_load(msg32[0], msg32[1], 0);
    cus_load(msg32[2], msg32[3], 2);
    cus_load(msg32[4], msg32[5], 4);
    cus_load(msg32[6], msg32[7], 6);
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
