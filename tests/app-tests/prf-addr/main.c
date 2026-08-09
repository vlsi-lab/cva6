/* prf-addr.c — PRF_ADDR (secret-key-seed keyed PRF) SW-vs-HW test.
 *
 * Computes the SPHINCS+/SLH-DSA SHAKE256 PRF_ADDR primitive two ways:
 *   1. Software reference (spx_ref_prf(), adapted from
 *      hash-spx/cva6/tests/sphincs_ref_impl.h, local copy in spx_ref_sw.h).
 *   2. Hardware via digsig's chain_job_ctrl MMIO register interface
 *      (vrf_chain.h), op_type = CA_OP_PRF_ADDR.
 *
 * Unlike THASH1/THASH2, PRF_ADDR has only a single ("simple"-equivalent)
 * construction: chain_job_ctrl.sv's FSM always skips the robust bitmask
 * branch for op_type == OP_PRF_ADDR (see its ST_SHAKE_WAIT1 case), so
 * there is no robust variant to exercise here.
 *
 * Covers security levels n = 16 (128-bit), 24 (192-bit) and 32 (256-bit)
 * bytes.
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
} prf_variant_t;

static const prf_variant_t k_variants[] = {
    {"SPHINCS+-128", 16},
    {"SPHINCS+-192", 24},
    {"SPHINCS+-256", 32},
};

/* Drive a single PRF_ADDR call through chain_job_ctrl and read back the
 * output. chain_job_ctrl's input_block1 (CHAIN register) supplies sk_seed
 * for this op_type (see chain_job_ctrl.sv's rate_1_* construction: seed_rev
 * || addr_rev || chain_rev, matching spx_ref_prf()'s
 * pub_seed || addr || sk_seed layout). */
static void prf_addr_hw_exec(uint8_t *out, const uint8_t *pub_seed,
                             const uint8_t *addr, const uint8_t *sk_seed,
                             size_t n) {
    ca_load_seed(pub_seed, (unsigned)n);
    ca_load_adrs(addr);
    ca_load_chain(sk_seed, (unsigned)n);

    CHAIN_REG[CA_CTRL] = CA_CTRL_GO(CA_OP_PRF_ADDR, 0, n, 1, 0);
    CA_WAIT_POLL;

    ca_read_chain(out, (unsigned)n);
}

static int run_prf_case(const prf_variant_t *v, uint32_t *sw_cycles,
                        uint32_t *hw_cycles, uint32_t seed) {
    uint8_t pub_seed[32] = {0};
    uint8_t sk_seed[32] = {0};
    uint8_t addr[SPX_ADDR_BYTES] = {0};
    uint8_t out_sw[32] = {0};
    uint8_t out_hw[32] = {0};
    uint32_t c_sw = 0;
    uint32_t c_hw = 0;

    spx_fill_bytes(pub_seed, v->n, (uint32_t)(0x1000 + seed + v->n));
    spx_fill_bytes(sk_seed, v->n, (uint32_t)(0x2000 + seed + v->n));
    spx_fill_bytes(addr, SPX_ADDR_BYTES, (uint32_t)(0x3000 + seed + v->n));

    write_csr(mcycle, 0);
    spx_ref_prf(out_sw, pub_seed, sk_seed, addr, v->n);
    c_sw = (uint32_t)read_csr(mcycle);

    write_csr(mcycle, 0);
    prf_addr_hw_exec(out_hw, pub_seed, addr, sk_seed, v->n);
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
            int err = run_prf_case(&k_variants[i], &c_sw, &c_hw, tc);

            sw_total += c_sw;
            hw_total += c_hw;

            print_uart(k_variants[i].name);
            print_uart(" prf-addr case");
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
