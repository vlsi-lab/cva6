/*
 * hash_ip.h - C inline wrappers for the new HASH coprocessor ISA
 *
 * The HASH IP exposes 19 custom instructions on RISC-V opcode 0x5B.
 * All operands are 64-bit (XLEN=64).  The IP throttles `issue_ready` until
 * each multi-cycle operation finishes, so no NOP padding is required around
 * KSTART / KPERM / THASH* / PRF / CL_*.
 *
 * Encoding map (funct3 / funct7):
 *   f3=0,f7=0x00 OP_INIT            init register file
 *   f3=0,f7=0x01 OP_KSTART          start a Keccak absorb sequence
 *   f3=0,f7=0x02 OP_KPERM           Keccak-f[1600] in place
 *   f3=1,f7=0x00 OP_LOAD     rs1=data64 rs2=lane_idx
 *   f3=1,f7=0x01 OP_KABSORB  rs1=data64 rs2=lane_idx (XOR into lane)
 *   f3=2,f7=0x00 OP_STORE    rd=lane    rs1=lane_idx
 *   f3=2,f7=0x01 OP_KREAD3   rd=word    rs1=byte_off
 *   f3=3,f7=0x00 OP_THASH1   rs2=simple_flag (SHAKE128/SHA3-256 depending on cfg)
 *   f3=3,f7=0x01 OP_THASH2   rs2=simple_flag
 *   f3=3,f7=0x02 OP_PRF_ADDR
 *   f3=3,f7=0x03..0x08      THASH/PRF 192/256 variants
 *   f3=4,f7=0x00..0x02      CL_128F / CL_192F / CL_256F
 */

#ifndef HASH_IP_H
#define HASH_IP_H

#include <stdint.h>

/* ---------------- Keccak primitives ---------------- */

static inline void hash_init(void) {
    __asm__ volatile (".insn r 0x5b, 0, 0x00, x0, x0, x0" ::: "memory");
}

static inline void hash_kstart(void) {
    __asm__ volatile (".insn r 0x5b, 0, 0x01, x0, x0, x0" ::: "memory");
}

static inline void hash_kperm(void) {
    __asm__ volatile (".insn r 0x5b, 0, 0x02, x0, x0, x0" ::: "memory");
}

static inline void hash_load(uint64_t data, uint64_t idx) {
    __asm__ volatile (".insn r 0x5b, 1, 0x00, x0, %0, %1"
                      :: "r"(data), "r"(idx) : "memory");
}

static inline void hash_kabsorb(uint64_t data, uint64_t idx) {
    __asm__ volatile (".insn r 0x5b, 1, 0x01, x0, %0, %1"
                      :: "r"(data), "r"(idx) : "memory");
}

static inline uint64_t hash_store(uint64_t idx) {
    uint64_t r;
    __asm__ volatile (".insn r 0x5b, 2, 0x00, %0, %1, x0"
                      : "=r"(r) : "r"(idx) : "memory");
    return r;
}

static inline uint64_t hash_kread3(uint64_t byte_off) {
    uint64_t r;
    __asm__ volatile (".insn r 0x5b, 2, 0x01, %0, %1, x0"
                      : "=r"(r) : "r"(byte_off) : "memory");
    return r;
}

/* ---------------- SPHINCS+ thash / prf -------------- */

static inline void hash_thash1(uint64_t simple) {
    __asm__ volatile (".insn r 0x5b, 3, 0x00, x0, x0, %0"
                      :: "r"(simple) : "memory");
}
static inline void hash_thash2(uint64_t simple) {
    __asm__ volatile (".insn r 0x5b, 3, 0x01, x0, x0, %0"
                      :: "r"(simple) : "memory");
}
static inline void hash_prf_addr(void) {
    __asm__ volatile (".insn r 0x5b, 3, 0x02, x0, x0, x0" ::: "memory");
}
/* 192/256 variants */
static inline void hash_thash1_192(uint64_t simple) {
    __asm__ volatile (".insn r 0x5b, 3, 0x03, x0, x0, %0" :: "r"(simple) : "memory");
}
static inline void hash_thash2_192(uint64_t simple) {
    __asm__ volatile (".insn r 0x5b, 3, 0x04, x0, x0, %0" :: "r"(simple) : "memory");
}
static inline void hash_prf_addr_192(void) {
    __asm__ volatile (".insn r 0x5b, 3, 0x05, x0, x0, x0" ::: "memory");
}
static inline void hash_thash1_256(uint64_t simple) {
    __asm__ volatile (".insn r 0x5b, 3, 0x06, x0, x0, %0" :: "r"(simple) : "memory");
}
static inline void hash_thash2_256(uint64_t simple) {
    __asm__ volatile (".insn r 0x5b, 3, 0x07, x0, x0, %0" :: "r"(simple) : "memory");
}
static inline void hash_prf_addr_256(void) {
    __asm__ volatile (".insn r 0x5b, 3, 0x08, x0, x0, x0" ::: "memory");
}

/* ---------------- WOTS+ chain lengths --------------- */

static inline void hash_cl_128f(void) {
    __asm__ volatile (".insn r 0x5b, 4, 0x00, x0, x0, x0" ::: "memory");
}
static inline void hash_cl_192f(void) {
    __asm__ volatile (".insn r 0x5b, 4, 0x01, x0, x0, x0" ::: "memory");
}
static inline void hash_cl_256f(void) {
    __asm__ volatile (".insn r 0x5b, 4, 0x02, x0, x0, x0" ::: "memory");
}

/* ---------------- HORCRUX legacy compat layer ----------------
 *
 * The legacy HORCRUX register file was 50 x 32-bit; the new IP exposes
 * 25 x 64-bit lanes.  All HORCRUX wrappers below assume the old caller
 * uses an even 32-bit index `idx32` paired with an adjacent word, which
 * is the layout produced by every HORCRUX assembly source we ported.
 *
 *   lane64 = ((uint64_t)hi << 32) | lo
 *   lane_idx = idx32 / 2
 */

static inline void cus_load(uint32_t lo, uint32_t hi, uint32_t idx32) {
    uint64_t v = ((uint64_t)hi << 32) | (uint64_t)lo;
    hash_load(v, (uint64_t)(idx32 >> 1));
}

static inline uint32_t cus_store(uint32_t idx32) {
    uint64_t v = hash_store((uint64_t)(idx32 >> 1));
    return (idx32 & 1u) ? (uint32_t)(v >> 32) : (uint32_t)v;
}

static inline void keccak_hw_init(void) { hash_init(); }

static inline void keccak_hw_absorb_xor(uint32_t lo, uint32_t hi, uint32_t idx32) {
    uint64_t v = ((uint64_t)hi << 32) | (uint64_t)lo;
    hash_kabsorb(v, (uint64_t)(idx32 >> 1));
}

static inline void keccak_hw_permute(void) {
    /* Old PERMUTE = single Keccak-f in place. */
    hash_kperm();
}

/* Old keccak_hw_start: combined absorb+permute trigger.  In the new ISA we
 * model that as KSTART followed by KPERM. */
static inline void keccak_hw_start(void) {
    hash_kstart();
    hash_kperm();
}

static inline uint32_t keccak_hw_store_word(uint32_t idx32) {
    return cus_store(idx32);
}

/* Read 3 consecutive bytes starting at byte_off into the low 24 bits. */
static inline uint32_t keccak_hw_read3(uint32_t byte_off) {
    return (uint32_t)(hash_kread3((uint64_t)byte_off) & 0x00FFFFFFu);
}

/* HORCRUX names for the chain-length variants. */
static inline void cl_compute_128f(void) { hash_cl_128f(); }
static inline void cl_compute_192f(void) { hash_cl_192f(); }
static inline void cl_compute_256f(void) { hash_cl_256f(); }

/* HORCRUX names for the SPHINCS+ ops (default / "robust" form). */
static inline void thash1_hw_compute(void)    { hash_thash1(0); }
static inline void thash2_hw_compute(void)    { hash_thash2(0); }
static inline void prf_addr_hw_compute(void)  { hash_prf_addr();  }

#endif /* HASH_IP_H */
