/*
 * compat.h - X-HEEP / HORCRUX -> CVA6 test environment shim
 *
 * The HORCRUX SW tests include `core_v_mini_mcu.h` and `csr.h`, and use
 * the X-HEEP `CSR_WRITE / CSR_READ / CSR_REG_MCYCLE` macros to read the
 * RISC-V mcycle counter.  In the CVA6 verification flow we replace those
 * with thin wrappers around the standard `mcycle` CSR.
 *
 * Tests should `#include "../inc/compat.h"` in place of the X-HEEP headers.
 */

#ifndef HASH_TESTS_COMPAT_H
#define HASH_TESTS_COMPAT_H

#include <stdint.h>

/* RISC-V CSR addresses (priv-spec).  We pass them as numeric immediates
 * to the assembler (`csrw 0xB00, x10` is valid GAS syntax). */
#define CSR_REG_MCYCLE          0xB00
#define CSR_REG_MCOUNTINHIBIT   0x320

/* Two-level stringification so the CSR macro is expanded BEFORE being
 * turned into a string literal. */
#define _HASH_STR(x)   _HASH_STR_(x)
#define _HASH_STR_(x)  #x

/* Read a CSR into the variable pointed to by `dst`. */
#define CSR_READ(csr, dst) do {                                         \
    unsigned long __v;                                                  \
    __asm__ volatile ("csrr %0, " _HASH_STR(csr) : "=r"(__v));          \
    *(dst) = (uint32_t)__v;                                             \
} while (0)

/* Write a value to a CSR. */
#define CSR_WRITE(csr, val) do {                                        \
    unsigned long __v = (unsigned long)(val);                           \
    __asm__ volatile ("csrw " _HASH_STR(csr) ", %0" :: "r"(__v));       \
} while (0)

/* Atomic clear / set bits in a CSR (X-HEEP API). */
#define CSR_CLEAR_BITS(csr, mask) do {                                  \
    unsigned long __m = (unsigned long)(mask);                          \
    __asm__ volatile ("csrc " _HASH_STR(csr) ", %0" :: "r"(__m));       \
} while (0)

#define CSR_SET_BITS(csr, mask) do {                                    \
    unsigned long __m = (unsigned long)(mask);                          \
    __asm__ volatile ("csrs " _HASH_STR(csr) ", %0" :: "r"(__m));       \
} while (0)

/* Some HORCRUX sources read `core_v_mini_mcu.h` for SoC base addresses;
 * none of the ported tests actually use those, so we leave the header
 * intentionally empty. */

#endif /* HASH_TESTS_COMPAT_H */
