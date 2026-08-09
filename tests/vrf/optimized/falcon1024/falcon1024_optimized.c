///////////////////////////////////////////////////////////////////////////////////////
// Bare-metal CVA6 verify-only KAT test for falcon-1024 (vrf_ip-accelerated
// vrfy.c/shake.c), trimmed from the auto-generated static test
// (tools/gen_static_test.py output). This harness only exercises
// crypto_sign_open() -- keygen/sign are not run here (see tests/pqc/ for
// the full keygen+sign+verify baseline/optimized harness). The KAT's own
// pk/sm values are loaded directly instead of generating them. stdio's
// printf replaced with the simulated UART (print_uart/print_uart_dec);
// cycle counting via the RISC-V mcycle CSR, retired-instruction counting
// via minstret (encoding.h), same pattern as every other test in this repo.
///////////////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "api.h"
#include "test_vectors_1024.h"

#include "encoding.h"   /* read_csr / write_csr / clear_csr for mcycle/minstret */
#include "uart.h"       /* print_uart, print_uart_dec (replaces printf on CVA6) */

int main(void)
{
    uint8_t pk[CRYPTO_PUBLICKEYBYTES];
    uint8_t sm[MLEN_KAT + CRYPTO_BYTES];
    uint8_t m1[MLEN_KAT + CRYPTO_BYTES];
    unsigned long long smlen, mlen1;
    int fails = 0;
    unsigned int cycles, instrs, start_instret;

    /* Enable the hardware cycle counter (clear bit-0 of mcountinhibit) */
    clear_csr(mcountinhibit, 1);

    for (int i = 0; i < N_KAT; i++) {
        memcpy(pk, TVEC_OUT_PK[i], CRYPTO_PUBLICKEYBYTES);
        memcpy(sm, TVEC_IN_SM_SIGN[i], TVEC_IN_SM_SIGN_LEN[i]);
        smlen = TVEC_IN_SM_SIGN_LEN[i];

        write_csr(mcycle, 0);
        start_instret = (unsigned int)read_csr(minstret);
        crypto_sign_open(m1, &mlen1, sm, smlen, pk);
        cycles = (unsigned int)read_csr(mcycle);
        instrs = (unsigned int)read_csr(minstret) - start_instret;

        print_uart("Clock cycles [verify]: ");
        print_uart_dec((int)cycles);
        print_uart("\n");
        print_uart("Instructions [verify]: ");
        print_uart_dec((int)instrs);
        print_uart("\n");

        if (mlen1 != MLEN_KAT || memcmp(m1, TVEC_IN_M_SIGN[i], MLEN_KAT)) {
            fails++;
        }
    }

    return fails != 0;
}
