///////////////////////////////////////////////////////////////////////////////////////
// Bare-metal CVA6 adaptation of the auto-generated static (no file I/O) KAT test for
// falcon-512 (tools/gen_static_test.py output). stdio's printf replaced with the
// simulated UART (print_uart/print_uart_dec, same helpers used by tests/hawk512's
// main.c); cycle counting filled in via the RISC-V mcycle CSR (encoding.h), same
// read_csr(mcycle)/write_csr(mcycle,0) pattern as every other test in this repo.
///////////////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "api.h"
#include "test_vectors_512.h"

#include "encoding.h"   /* read_csr / write_csr / clear_csr for mcycle         */
#include "uart.h"       /* print_uart, print_uart_dec (replaces printf on CVA6) */

#define RUN_KEYGEN  1
#define RUN_SIGN    1
#define RUN_VERIFY  1

static void print_cycles(const char *label, unsigned int cyc)
{
    print_uart("Clock cycles [");
    print_uart(label);
    print_uart("]: ");
    print_uart_dec(cyc);
    print_uart("\n");
}

int main(void)
{
    uint8_t pk[CRYPTO_PUBLICKEYBYTES];
    uint8_t sk[CRYPTO_SECRETKEYBYTES];
    uint8_t m[MLEN_KAT];
    uint8_t sm[MLEN_KAT + CRYPTO_BYTES];
    uint8_t m1[MLEN_KAT + CRYPTO_BYTES];
    unsigned long long smlen, mlen1;
    int fails = 0;
    unsigned int cycles;

    /* Enable the hardware cycle counter (clear bit-0 of mcountinhibit) */
    clear_csr(mcountinhibit, 1);

    for (int i = 0; i < N_KAT; i++) {
        print_uart("=== KAT ");
        print_uart_dec(i + 1);
        print_uart("/");
        print_uart_dec(N_KAT);
        print_uart(" ===\n");
        memcpy(m, TVEC_IN_M_SIGN[i], MLEN_KAT);

#if RUN_KEYGEN
        write_csr(mcycle, 0);
        crypto_sign_keypair(pk, sk, TVEC_KEYPAIR_RND[i]);
        cycles = (unsigned int)read_csr(mcycle);
        print_cycles("keygen", cycles);

        if (memcmp(pk, TVEC_OUT_PK[i], CRYPTO_PUBLICKEYBYTES)) {
            print_uart("["); print_uart_dec(i); print_uart("] ERROR: PK mismatch\n");
            fails++;
        }
        if (memcmp(sk, TVEC_OUT_SK[i], CRYPTO_SECRETKEYBYTES)) {
            print_uart("["); print_uart_dec(i); print_uart("] ERROR: SK mismatch\n");
            fails++;
        }
#else
        memcpy(pk, TVEC_OUT_PK[i], CRYPTO_PUBLICKEYBYTES);
        memcpy(sk, TVEC_OUT_SK[i], CRYPTO_SECRETKEYBYTES);
#endif /* RUN_KEYGEN */

#if RUN_SIGN
        write_csr(mcycle, 0);
        crypto_sign(sm, &smlen, m, MLEN_KAT, sk, TVEC_NONCE[i], TVEC_SIGN_RND[i]);
        cycles = (unsigned int)read_csr(mcycle);
        print_cycles("sign", cycles);

        if (smlen != TVEC_IN_SM_SIGN_LEN[i] || memcmp(sm, TVEC_IN_SM_SIGN[i], TVEC_IN_SM_SIGN_LEN[i])) {
            print_uart("["); print_uart_dec(i); print_uart("] ERROR: SM mismatch\n");
            fails++;
        }
#else
        memcpy(sm, TVEC_IN_SM_SIGN[i], TVEC_IN_SM_SIGN_LEN[i]);
        smlen = TVEC_IN_SM_SIGN_LEN[i];
#endif /* RUN_SIGN */

#if RUN_VERIFY
        write_csr(mcycle, 0);
        crypto_sign_open(m1, &mlen1, sm, smlen, pk);
        cycles = (unsigned int)read_csr(mcycle);
        print_cycles("verify", cycles);

        if (mlen1 != MLEN_KAT || memcmp(m1, TVEC_IN_M_SIGN[i], MLEN_KAT)) {
            print_uart("["); print_uart_dec(i); print_uart("] ERROR: M mismatch\n");
            fails++;
        }
#endif /* RUN_VERIFY */
    }

    if (fails == 0) {
        print_uart("Test Successful (");
        print_uart_dec(N_KAT);
        print_uart(" KAT vector(s))\n");
    } else {
        print_uart("Test FAILED: ");
        print_uart_dec(fails);
        print_uart(" mismatch(es)\n");
    }

    return fails != 0;
}
