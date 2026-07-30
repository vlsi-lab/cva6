// GF(2) multiply-reduce Accelerator IP -- software driver
// Mirrors tests/keccak64/keccak_axi.c's raw-MMIO-pointer, poll-based style.
//
// GF2_BASE_ADDR here MUST be kept in sync with corev_apu/tb/ariane_soc_pkg.sv's
// Gf2Base by hand -- same caveat keccak_axi.c already has for KECCAK_BASE_ADDR.
//
// Operands are plain uint64_t[] word arrays (values[0] = low limb, ...), not
// bf128_t/bf384_t directly -- same independence from FAEST's internal types
// cwrash's gf2_hal.h has from bf128_t/bf384_t; the FAEST-side port (later)
// converts at the call site via BF_VALUE/BF384_WORD.

#ifndef _GF2_HAL_H_
#define _GF2_HAL_H_

#include <stdint.h>
#include "gf2_axi.h"

#define GF2_BASE_ADDR 0x70000000

// aes_ip's identical reggen/axi_to_reg register-file pattern was found (via
// aes_hal.h) to return a stale RESULT value for a variable number of reads
// immediately after the STATUS poll loop confirms READY -- the stale value
// itself stays consistent across several back-to-back reads before flipping
// to the correct one, so a fixed 1-read discard or a "two matching reads"
// debounce were both insufficient. Applying the same generous fixed-margin
// discard here proactively, since gf2_axi_top.sv shares the exact same
// register-file/AXI bridge construction.
#define GF2_RESULT_READ_MARGIN 32
static inline uint64_t _gf2_read_stable(volatile uint64_t *reg)
{
    int i;
    uint64_t v = *reg;
    for (i = 0; i < GF2_RESULT_READ_MARGIN; i++) v = *reg;
    return v;
}

static inline void gf2_mul128_hw(uint64_t result[2], const uint64_t lhs[2], const uint64_t rhs[2])
{
    volatile uint64_t *lhsregs = (volatile uint64_t *) (GF2_BASE_ADDR + GF2_LHS128_0_REG_OFFSET);
    volatile uint64_t *rhsregs = (volatile uint64_t *) (GF2_BASE_ADDR + GF2_RHS_0_REG_OFFSET);
    volatile uint64_t *resregs = (volatile uint64_t *) (GF2_BASE_ADDR + GF2_RES128_0_REG_OFFSET);
    volatile uint64_t *ctrl    = (volatile uint64_t *) (GF2_BASE_ADDR + GF2_CTRL_REG_OFFSET);
    volatile uint64_t *status  = (volatile uint64_t *) (GF2_BASE_ADDR + GF2_STATUS_REG_OFFSET);

    lhsregs[0] = lhs[0]; lhsregs[1] = lhs[1];
    rhsregs[0] = rhs[0]; rhsregs[1] = rhs[1];

    *ctrl = (1ULL << GF2_CTRL_NEXT_BIT);   // mode384=0
    while (((*status) & (1ULL << GF2_STATUS_READY_BIT)) == 0) { }

    result[0] = _gf2_read_stable(&resregs[0]);
    result[1] = _gf2_read_stable(&resregs[1]);

    *ctrl = 0;
}

static inline void gf2_mul384_128_hw(uint64_t lhs[6], const uint64_t rhs[2])
{
    volatile uint64_t *lhsregs = (volatile uint64_t *) (GF2_BASE_ADDR + GF2_LHS384_0_REG_OFFSET);
    volatile uint64_t *rhsregs = (volatile uint64_t *) (GF2_BASE_ADDR + GF2_RHS_0_REG_OFFSET);
    volatile uint64_t *resregs = (volatile uint64_t *) (GF2_BASE_ADDR + GF2_RES384_0_REG_OFFSET);
    volatile uint64_t *ctrl    = (volatile uint64_t *) (GF2_BASE_ADDR + GF2_CTRL_REG_OFFSET);
    volatile uint64_t *status  = (volatile uint64_t *) (GF2_BASE_ADDR + GF2_STATUS_REG_OFFSET);
    int i;

    for (i = 0; i < 6; i++) lhsregs[i] = lhs[i];
    rhsregs[0] = rhs[0]; rhsregs[1] = rhs[1];

    *ctrl = (1ULL << GF2_CTRL_NEXT_BIT) | (1ULL << GF2_CTRL_MODE384_BIT);
    while (((*status) & (1ULL << GF2_STATUS_READY_BIT)) == 0) { }

    for (i = 0; i < 6; i++) lhs[i] = _gf2_read_stable(&resregs[i]);

    *ctrl = 0;
}

// _GF2_HAL_H_
#endif
