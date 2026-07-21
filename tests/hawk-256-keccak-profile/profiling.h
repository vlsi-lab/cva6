#ifndef HAWK_PROFILING_H__
#define HAWK_PROFILING_H__

/*
 * Cycle-profiling helpers for CVA6 bare-metal.
 *
 * PROF_LEVEL (compile-time, -DPROF_LEVEL=N) controls which probe levels
 * are compiled in:
 *   0  — all macros compile to nothing, zero overhead
 *   1  — L1 probes compiled in
 *   2  — L1 + L2 probes compiled in
 *   3  — L1 + L2 + L3 probes compiled in
 *
 * prof_print_level (runtime global, set from main.c) controls printing:
 *   0  — print nothing
 *   1  — print L1 only
 *   2  — print L1 + L2
 *   3  — print L1 + L2 + L3
 *
 * Timing is delta-based: PROF_BEGINn saves the current mcycle value into a
 * per-level static variable; PROF_ENDn computes (current - saved).  Nested
 * probes at different levels do NOT interfere with each other, so L1 and L2
 * measurements are both accurate when PROF_LEVEL >= 2.
 *
 * L1 labels (called directly from keygen / sign / verify wrappers):
 *   keygen : Hawk_keygen, encode_public, encode_private
 *   sign   : Hawk_regen_fg, sign_hm, sign_h, sign_basis_m2_mul,
 *             sign_sig_gauss, sign_ntt_s1, sign_poly_symbreak,
 *             sign_encode_sig
 *   verify : decode_public_key, decode_signature, verify_inner
 *
 * L2 labels (sub-subfunctions):
 *   keygen : encode_gr_q00, encode_gr_q01,
 *             extract_lowbit_F, extract_lowbit_G, encode_private_shake
 *   verify : vrfy_shake, vrfy_t1_fft, vrfy_q00_fft, vrfy_q01_fft,
 *             vrfy_div_ifft, vrfy_s0_t0, vrfy_ntt_norm
 */

#ifndef PROF_LEVEL
#define PROF_LEVEL 0
#endif

#include <stdint.h>
#include "encoding.h"

/* Minimal UART helpers (avoids uart.h's non-static bin_to_hex_table). */
#define _PROF_UART_THR  ((volatile uint8_t *)0x10000000UL)
#define _PROF_UART_LSR  ((volatile uint8_t *)0x10000014UL)

static inline void _prof_putc(char c)
{
    while (!(*_PROF_UART_LSR & 0x20)) {}
    *_PROF_UART_THR = (uint8_t)c;
}

static inline void _prof_puts(const char *s)
{
    while (*s) _prof_putc(*s++);
}

static inline void _prof_putu(unsigned int v)
{
    if (v >= 10) _prof_putu(v / 10);
    _prof_putc('0' + (v % 10));
}

static inline void print_cycles(const char *label, unsigned int cyc)
{
    _prof_puts("Clock cycles [");
    _prof_puts(label);
    _prof_puts("]: ");
    _prof_putu(cyc);
    _prof_putc('\n');
}

/*
 * Runtime flag — set this from main() before each call to control which
 * profiling level is printed.  0 = silent; 1 = L1; 2 = L1+L2; 3 = L1+L2+L3.
 * Defined in main.c; declared extern here so every TU that includes this
 * header can read it without extra plumbing.
 */
extern int prof_print_level;

/* --- Level 1 ------------------------------------------------------------ */
#if PROF_LEVEL >= 1
static unsigned int _prof_start1;
# define PROF_BEGIN1() \
    (_prof_start1 = (unsigned int)read_csr(mcycle))
# define PROF_END1(lbl) \
    do { if (prof_print_level >= 1) { \
        print_cycles(lbl, (unsigned int)read_csr(mcycle) - _prof_start1); \
    } } while (0)
#else
# define PROF_BEGIN1()     ((void)0)
# define PROF_END1(lbl)    ((void)0)
#endif

/* --- Level 2 ------------------------------------------------------------ */
#if PROF_LEVEL >= 2
static unsigned int _prof_start2;
# define PROF_BEGIN2() \
    (_prof_start2 = (unsigned int)read_csr(mcycle))
# define PROF_END2(lbl) \
    do { if (prof_print_level >= 2) { \
        print_cycles(lbl, (unsigned int)read_csr(mcycle) - _prof_start2); \
    } } while (0)
#else
# define PROF_BEGIN2()     ((void)0)
# define PROF_END2(lbl)    ((void)0)
#endif

/* --- Level 3 ------------------------------------------------------------ */
#if PROF_LEVEL >= 3
static unsigned int _prof_start3;
# define PROF_BEGIN3() \
    (_prof_start3 = (unsigned int)read_csr(mcycle))
# define PROF_END3(lbl) \
    do { if (prof_print_level >= 3) { \
        print_cycles(lbl, (unsigned int)read_csr(mcycle) - _prof_start3); \
    } } while (0)
#else
# define PROF_BEGIN3()     ((void)0)
# define PROF_END3(lbl)    ((void)0)
#endif

#endif /* HAWK_PROFILING_H__ */
