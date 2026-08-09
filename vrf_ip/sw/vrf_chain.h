/* vrf_chain.h — SPHINCS+/SLH-DSA hash-chain job driver for the shared VRF
 * accelerator (chain_job_ctrl.sv, dispatched via vrf_axi_top's CHAIN_*
 * registers -- see vrf_axi.h, generated from vrf_ip/vrf.hjson).
 *
 * Drop-in replacement for the old (now-retired) hashpq_ip/sw/hal_cva6.h:
 * same op_type/CA_* naming and ca_load_* / ca_read_chain / CA_WAIT_POLL
 * call shape, retargeted from chain_top's 8x32-bit CHAIN/SEED/ADDR/CHAIN2
 * register bank onto chain_job_ctrl's 4x64-bit CHAIN_IO/CHAIN_SEED/
 * CHAIN_ADRS/CHAIN_IN2 multiregs and CHAIN_CTRL's combined go/done/robust/
 * n/steps/step_start/op_type bit layout (matching every other job on this
 * accelerator -- see NTT_CTRL/REJ_CTRL/JOBCTRL in vrf_axi.h).
 *
 * Byte convention: word i of each multireg holds buffer bytes [8i..8i+7],
 * byte 8i at bits [7:0] of word i -- a raw little-endian reinterpret-cast
 * of the host byte buffer (see chain_job_ctrl.sv's header comment).
 *
 * CHAIN_CTRL is a combined control+status register like NTT_CTRL/REJ_CTRL:
 * there is no separate STATUS register. Unlike chain_accel.sv (which
 * auto-returned to IDLE the cycle after DONE), chain_job_ctrl.sv holds
 * DONE_HOLD until software clears CTRL.GO -- CA_WAIT_POLL below does that
 * clear itself so every existing call site (poll-then-immediately-read)
 * stays correct without needing to know about it.
 */

#ifndef VRF_CHAIN_H
#define VRF_CHAIN_H

#include <stdint.h>
#include <stddef.h>
#include "vrf_axi.h"

/* === Base address === */
#ifndef VRF_AXI_BASE_ADDR
#define VRF_AXI_BASE_ADDR 0x50000000u
#endif
#define CHAIN_BASE VRF_AXI_BASE_ADDR

/* === chain_job_ctrl register offsets, as 64-bit-word indices (byte offset
 * / 8 -- every offset in vrf.hjson's CHAIN_* registers is 8-byte aligned,
 * since the whole register file is 64-bit-wide) === */
#define CA_CHAIN_SEED_0 (VRF_CHAIN_SEED_0_REG_OFFSET / 8)
#define CA_CHAIN_SEED_1 (VRF_CHAIN_SEED_1_REG_OFFSET / 8)
#define CA_CHAIN_SEED_2 (VRF_CHAIN_SEED_2_REG_OFFSET / 8)
#define CA_CHAIN_SEED_3 (VRF_CHAIN_SEED_3_REG_OFFSET / 8)
#define CA_CHAIN_ADRS_0 (VRF_CHAIN_ADRS_0_REG_OFFSET / 8)
#define CA_CHAIN_ADRS_1 (VRF_CHAIN_ADRS_1_REG_OFFSET / 8)
#define CA_CHAIN_ADRS_2 (VRF_CHAIN_ADRS_2_REG_OFFSET / 8)
#define CA_CHAIN_ADRS_3 (VRF_CHAIN_ADRS_3_REG_OFFSET / 8)
#define CA_CHAIN_IN2_0  (VRF_CHAIN_IN2_0_REG_OFFSET / 8)
#define CA_CHAIN_IN2_1  (VRF_CHAIN_IN2_1_REG_OFFSET / 8)
#define CA_CHAIN_IN2_2  (VRF_CHAIN_IN2_2_REG_OFFSET / 8)
#define CA_CHAIN_IN2_3  (VRF_CHAIN_IN2_3_REG_OFFSET / 8)
#define CA_CHAIN_IO_0   (VRF_CHAIN_IO_0_REG_OFFSET / 8)
#define CA_CHAIN_IO_1   (VRF_CHAIN_IO_1_REG_OFFSET / 8)
#define CA_CHAIN_IO_2   (VRF_CHAIN_IO_2_REG_OFFSET / 8)
#define CA_CHAIN_IO_3   (VRF_CHAIN_IO_3_REG_OFFSET / 8)
#define CA_CTRL         (VRF_CHAIN_CTRL_REG_OFFSET / 8)

/* === op_type constants (CHAIN_CTRL.OP_TYPE) === */
#define CA_OP_PRF_ADDR 0u
#define CA_OP_THASH1   1u
#define CA_OP_THASH2   2u

/* === CTRL construction macro === */
#define CA_CTRL_GO(op_type, robust, n, steps, step_start) \
    ( (1u << VRF_CHAIN_CTRL_GO_BIT) \
    | ((robust) ? (1u << VRF_CHAIN_CTRL_ROBUST_BIT) : 0u) \
    | (((uint32_t)(step_start)) << VRF_CHAIN_CTRL_STEP_START_OFFSET) \
    | (((uint32_t)(steps))      << VRF_CHAIN_CTRL_STEPS_OFFSET) \
    | (((uint32_t)(n))          << VRF_CHAIN_CTRL_N_OFFSET) \
    | (((uint32_t)(op_type))    << VRF_CHAIN_CTRL_OP_TYPE_OFFSET) )

/* === Volatile register array (64-bit-word indexed) === */
#define CHAIN_REG ((volatile uint64_t *)(VRF_AXI_BASE_ADDR))

/* === Poll for completion, then clear GO so chain_job_ctrl's DONE_HOLD
 * returns to IDLE and job_go_rise re-arms for the next call === */
#define CA_WAIT_POLL \
    { while (!(CHAIN_REG[CA_CTRL] & (1u << VRF_CHAIN_CTRL_DONE_BIT))) ; \
      CHAIN_REG[CA_CTRL] = 0; }

/* === Inline register-load helpers === */

static inline void ca_load_chain(const uint8_t *chain, unsigned n)
{
    volatile uint64_t *r = CHAIN_REG;
    const uint64_t *c = (const uint64_t *)chain;
    unsigned words = n >> 3;
    unsigned i;
    for (i = 0; i < words; i++)
        r[CA_CHAIN_IO_0 + i] = c[i];
    for (; i < 4u; i++)
        r[CA_CHAIN_IO_0 + i] = 0u;
}

static inline void ca_read_chain(uint8_t *chain_out, unsigned n)
{
    volatile uint64_t *r = CHAIN_REG;
    uint64_t *c = (uint64_t *)chain_out;
    unsigned words = n >> 3;
    for (unsigned i = 0; i < words; i++)
        c[i] = r[CA_CHAIN_IO_0 + i];
}

static inline void ca_load_seed(const uint8_t *seed, unsigned n)
{
    volatile uint64_t *r = CHAIN_REG;
    const uint64_t *s = (const uint64_t *)seed;
    unsigned words = n >> 3;
    unsigned i;
    for (i = 0; i < words; i++)
        r[CA_CHAIN_SEED_0 + i] = s[i];
    for (; i < 4u; i++)
        r[CA_CHAIN_SEED_0 + i] = 0u;
}

static inline void ca_load_adrs(const uint8_t *adrs)
{
    volatile uint64_t *r = CHAIN_REG;
    const uint64_t *a = (const uint64_t *)adrs;
    r[CA_CHAIN_ADRS_0] = a[0]; r[CA_CHAIN_ADRS_1] = a[1];
    r[CA_CHAIN_ADRS_2] = a[2]; r[CA_CHAIN_ADRS_3] = a[3];
}

static inline void ca_load_chain2(const uint8_t *chain2, unsigned n)
{
    volatile uint64_t *r = CHAIN_REG;
    const uint64_t *c = (const uint64_t *)chain2;
    unsigned words = n >> 3;
    unsigned i;
    for (i = 0; i < words; i++)
        r[CA_CHAIN_IN2_0 + i] = c[i];
    for (; i < 4u; i++)
        r[CA_CHAIN_IN2_0 + i] = 0u;
}

#endif /* VRF_CHAIN_H */
