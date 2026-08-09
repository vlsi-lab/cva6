/* thash.c — THASH1 (F function, single input block) SW-vs-HW test.
 *
 * Computes the SPHINCS+/SLH-DSA SHAKE256 THASH1 primitive two ways:
 *   1. Software reference (spx_ref_thash(), adapted from
 *      hash-spx/cva6/tests/sphincs_ref_impl.h, local copy in spx_ref_sw.h).
 *   2. Hardware via digsig's chain_job_ctrl MMIO register interface
 *      (vrf_chain.h), op_type = CA_OP_THASH1.
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

/* ADRS byte 31: the WOTS+ chain "hash address" field (SPX_OFFSET_HASH_ADDR
 * per address.c/shake_offsets.h). For op_type=THASH1, chain_job_ctrl.sv
 * always overlays the job's step_cnt (initialized from CHAIN_CTRL.STEP_START)
 * into this byte of the loaded ADRS -- the byte itself is a don't-care as
 * loaded via ca_load_adrs(). To match an arbitrary reference ADRS (as used
 * by spx_ref_thash() here, which uses addr[] verbatim with no override),
 * step_start must be set to the actual addr[SPX_OFFSET_HASH_ADDR] value. */
#define SPX_OFFSET_HASH_ADDR 31

/* Drive a single THASH1 call through chain_job_ctrl and read back the digest. */
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

    spx_fill_bytes(pub_seed, v->n, (uint32_t)(0x4000 + seed + v->n + (v->simple_mode * 11)));
    spx_fill_bytes(addr, SPX_ADDR_BYTES, (uint32_t)(0x5000 + seed + v->n + (v->simple_mode * 19)));
    spx_fill_bytes(in, v->n, (uint32_t)(0x6000 + seed + v->n + (v->simple_mode * 23)));

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

int main(void) {
    int failures = 0;
    uint32_t sw_total = 0;
    uint32_t hw_total = 0;

    clear_csr(mcountinhibit, 1);

    for (size_t i = 0; i < sizeof(k_variants) / sizeof(k_variants[0]); i++) {
        for (uint32_t tc = 0; tc < 2; tc++) {
            uint32_t c_sw = 0;
            uint32_t c_hw = 0;
            int err = run_thash1_case(&k_variants[i], &c_sw, &c_hw, tc);

            sw_total += c_sw;
            hw_total += c_hw;

            print_uart(k_variants[i].name);
            print_uart(" thash1 case");
            print_uart_dec((int)(tc + 1));
            print_uart(": ");
            print_uart(err ? "[FAIL]" : "[PASS]");
            print_uart(" | SW=");
            print_uart_dec((int)c_sw);
            print_uart(" HW=");
            print_uart_dec((int)c_hw);
            print_uart("\n");

            failures += err;
        }
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
