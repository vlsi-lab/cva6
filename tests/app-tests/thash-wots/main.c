/* thash-wots.c — WOTS+ hash-chain SW-vs-HW test.
 *
 * Exercises a real WOTS+ hash chain: repeated SHAKE256 THASH1 (F function)
 * applications, each one keyed by an ADRS whose "hash address" byte
 * (ADRS byte 31, SPX_OFFSET_HASH_ADDR per the SPHINCS+ SHAKE reference --
 * see hash-spx/cva6/tests/pqc/optimized/DS/SLH-DSA/SPHINCS-256f-robust/
 * wots.c's gen_chain()/set_hash_addr()) is incremented on every step:
 *   out = F(pub_seed, ADRS_i, F(pub_seed, ADRS_{i-1}, ... F(pub_seed, ADRS_0, in)))
 *
 * Two ways:
 *   1. Software reference: a plain SW loop calling spx_ref_thash()
 *      `steps` times, incrementing addr[31] each iteration (local copy of
 *      hash-spx/cva6/tests/sphincs_ref_impl.h's spx_ref_thash(), see
 *      spx_ref_sw.h).
 *   2. Hardware: a *single* chain_job_ctrl MMIO CA_CTRL_GO call with
 *      steps > 1 -- chain_job_ctrl.sv's FSM internally loops
 *      step_cnt = step_start_r .. step_start_r+steps_r-1, feeding each
 *      step's output digest back as the next step's input (chain_r is
 *      both the input register and, after ST_SHAKE_POST, the output
 *      register) and overlaying the current step_cnt into ADRS byte 31
 *      (addr7_eff) for op_type=THASH1, exactly matching the SW loop's
 *      addr[31] = step_start + i sequence.
 *
 * A plain single-call THASH1 sanity case (mirroring tests/app-tests/thash)
 * is also included first, to isolate a chain-stepping bug from a base
 * THASH1 bug should either fail.
 *
 * Covers both the "simple" and "robust" NIST constructions at security
 * levels n = 16 (128-bit), 24 (192-bit) and 32 (256-bit) bytes.
 */

#include <stdint.h>
#include <string.h>

#include "encoding.h"
#include "spx_ref_sw.h"
#include "vrf_chain.h"
#include "uart.h"

/* ADRS byte 31: the WOTS+ chain "hash address" field (SPX_OFFSET_HASH_ADDR
 * per address.c/shake_offsets.h), the byte chain_job_ctrl.sv overlays with
 * the current step_cnt for op_type=THASH1. */
#define SPX_OFFSET_HASH_ADDR 31

/* Number of chain steps to exercise and the initial step index -- small
 * enough to keep simulation time reasonable, large enough (>1, spanning a
 * step_start offset) to genuinely exercise steps_r/step_start_r. */
#define WOTS_CHAIN_STEPS 6
#define WOTS_CHAIN_START 3

typedef struct {
    const char *name;
    size_t n;
    int simple_mode;
} thash_variant_t;

static const thash_variant_t k_variants[] = {
    {"SPHINCS+-128f-robust", 16, 0},
    {"SPHINCS+-128f-simple", 16, 1},
    {"SPHINCS+-192f-robust", 24, 0},
    {"SPHINCS+-192f-simple", 24, 1},
    {"SPHINCS+-256f-robust", 32, 0},
    {"SPHINCS+-256f-simple", 32, 1},
};

/* Single THASH1 call, mirroring tests/app-tests/thash's basic sanity case.
 * step_start must carry the real addr[SPX_OFFSET_HASH_ADDR] byte (not 0):
 * chain_job_ctrl.sv overlays step_cnt (initialized from step_start) into
 * that byte for every op_type=THASH1 job, so leaving step_start at 0 would
 * silently diverge from spx_ref_thash()'s use of addr[] verbatim whenever
 * the generated addr[31] isn't already 0. */
static void thash1_hw_exec(uint8_t *out, const uint8_t *pub_seed,
                           const uint8_t *addr, const uint8_t *in,
                           size_t n, int simple_mode) {
    ca_load_seed(pub_seed, (unsigned)n);
    ca_load_adrs(addr);
    ca_load_chain(in, (unsigned)n);

    CHAIN_REG[CA_CTRL] = CA_CTRL_GO(CA_OP_THASH1, !simple_mode, n, 1,
                                    addr[SPX_OFFSET_HASH_ADDR]);
    CA_WAIT_POLL;

    ca_read_chain(out, (unsigned)n);
}

static int run_thash1_case(const thash_variant_t *v, uint32_t *sw_cycles,
                           uint32_t *hw_cycles, uint32_t seed) {
    uint8_t pub_seed[32] = {0};
    uint8_t addr[SPX_ADDR_BYTES] = {0};
    uint8_t in[32] = {0};
    uint8_t out_sw[32] = {0};
    uint8_t out_hw[32] = {0};
    uint32_t c_sw = 0;
    uint32_t c_hw = 0;

    spx_fill_bytes(pub_seed, v->n, (uint32_t)(0xA000 + seed + v->n + (v->simple_mode * 5)));
    spx_fill_bytes(addr, SPX_ADDR_BYTES, (uint32_t)(0xB000 + seed + v->n + (v->simple_mode * 7)));
    spx_fill_bytes(in, v->n, (uint32_t)(0xC000 + seed + v->n + (v->simple_mode * 11)));

    write_csr(mcycle, 0);
    spx_ref_thash(out_sw, in, 1, pub_seed, addr, v->n, v->simple_mode);
    c_sw = (uint32_t)read_csr(mcycle);

    write_csr(mcycle, 0);
    thash1_hw_exec(out_hw, pub_seed, addr, in, v->n, v->simple_mode);
    c_hw = (uint32_t)read_csr(mcycle);

    if (sw_cycles != NULL) {
        *sw_cycles = c_sw;
    }
    if (hw_cycles != NULL) {
        *hw_cycles = c_hw;
    }

    return spx_compare_arrays(out_sw, out_hw, v->n) != 0;
}

/* A single chain_job_ctrl GO with steps=WOTS_CHAIN_STEPS runs the whole WOTS+
 * chain in hardware; the SW reference loops spx_ref_thash() the same
 * number of times, incrementing addr[SPX_OFFSET_HASH_ADDR] to match. */
static int run_wots_chain_case(const thash_variant_t *v, uint32_t *sw_cycles,
                               uint32_t *hw_cycles) {
    uint8_t pub_seed[32] = {0};
    uint8_t addr[SPX_ADDR_BYTES] = {0};
    uint8_t state_sw[32] = {0};
    uint8_t state_hw[32] = {0};
    uint32_t c_sw = 0;
    uint32_t c_hw = 0;
    uint32_t i;

    spx_fill_bytes(pub_seed, v->n, (uint32_t)(0xD000 + v->n + (v->simple_mode * 17)));
    spx_fill_bytes(addr, SPX_ADDR_BYTES, (uint32_t)(0xE000 + v->n + (v->simple_mode * 19)));
    spx_fill_bytes(state_sw, v->n, (uint32_t)(0xF000 + v->n + (v->simple_mode * 23)));
    memcpy(state_hw, state_sw, v->n);

    /* --- SW reference: WOTS_CHAIN_STEPS successive THASH1 calls --- */
    write_csr(mcycle, 0);
    for (i = 0; i < WOTS_CHAIN_STEPS; i++) {
        addr[SPX_OFFSET_HASH_ADDR] = (uint8_t)(WOTS_CHAIN_START + i);
        spx_ref_thash(state_sw, state_sw, 1, pub_seed, addr, v->n, v->simple_mode);
    }
    c_sw = (uint32_t)read_csr(mcycle);

    /* --- HW: one CA_CTRL_GO with steps=WOTS_CHAIN_STEPS, step_start=
     * WOTS_CHAIN_START. The low byte of ADDR[7] (addr[31]) is don't-care
     * here -- chain_job_ctrl.sv overlays step_cnt into it every step. --- */
    write_csr(mcycle, 0);
    ca_load_seed(pub_seed, (unsigned)v->n);
    ca_load_adrs(addr);
    ca_load_chain(state_hw, (unsigned)v->n);
    CHAIN_REG[CA_CTRL] = CA_CTRL_GO(CA_OP_THASH1, !v->simple_mode, v->n,
                                    WOTS_CHAIN_STEPS, WOTS_CHAIN_START);
    CA_WAIT_POLL;
    ca_read_chain(state_hw, (unsigned)v->n);
    c_hw = (uint32_t)read_csr(mcycle);

    if (sw_cycles != NULL) {
        *sw_cycles = c_sw;
    }
    if (hw_cycles != NULL) {
        *hw_cycles = c_hw;
    }

    return spx_compare_arrays(state_sw, state_hw, v->n) != 0;
}

int main(void) {
    int failures = 0;
    uint32_t sw_total = 0;
    uint32_t hw_total = 0;

    clear_csr(mcountinhibit, 1);

    for (size_t i = 0; i < sizeof(k_variants) / sizeof(k_variants[0]); i++) {
        uint32_t sw1 = 0, hw1 = 0;
        uint32_t sw2 = 0, hw2 = 0;
        int e1 = run_thash1_case(&k_variants[i], &sw1, &hw1, 0);
        int e2 = run_wots_chain_case(&k_variants[i], &sw2, &hw2);

        sw_total += sw1 + sw2;
        hw_total += hw1 + hw2;
        failures += e1 + e2;

        print_uart(k_variants[i].name);
        print_uart(" thash1: ");
        print_uart(e1 ? "[FAIL]" : "[PASS]");
        print_uart(" | SW=");
        print_uart_dec((int)sw1);
        print_uart(" HW=");
        print_uart_dec((int)hw1);
        print_uart("\n");

        print_uart(k_variants[i].name);
        print_uart(" wots-chain(");
        print_uart_dec(WOTS_CHAIN_STEPS);
        print_uart(" steps): ");
        print_uart(e2 ? "[FAIL]" : "[PASS]");
        print_uart(" | SW=");
        print_uart_dec((int)sw2);
        print_uart(" HW=");
        print_uart_dec((int)hw2);
        print_uart("\n");
    }

    if (sw_total > 0 && hw_total > 0) {
        print_uart("SW cycles: ");
        print_uart_dec((int)sw_total);
        print_uart("\n");
        print_uart("HW cycles: ");
        print_uart_dec((int)hw_total);
        print_uart("\n");
        print_uart("Speedup: ");
        print_uart_dec((int)(sw_total / hw_total));
        print_uart(".");
        {
            uint32_t frac = ((sw_total * 100) / hw_total) % 100;
            if (frac < 10) {
                print_uart("0");
            }
            print_uart_dec((int)frac);
        }
        print_uart("x\n");
    }

    if (failures == 0) {
        print_uart("FINAL STATUS: ALL TESTS PASSED\n");
    } else {
        print_uart("FINAL STATUS: ");
        print_uart_dec(failures);
        print_uart(" TEST(S) FAILED\n");
    }

    return failures;
}
