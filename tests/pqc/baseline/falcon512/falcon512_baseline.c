///////////////////////////////////////////////////////////////////////////////////////
// Bare-metal CVA6 adaptation of the auto-generated static (no file I/O) KAT test for
// falcon-512 (tools/gen_static_test.py output). stdio's printf replaced with the
// simulated UART (print_uart/print_uart_dec); cycle counting filled in via the RISC-V mcycle CSR (encoding.h), same
// read_csr(mcycle)/write_csr(mcycle,0) pattern as every other test in this repo.
///////////////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "api.h"
#include "test_vectors_512.h"

#include "encoding.h"   /* read_csr / write_csr / clear_csr for mcycle         */
#include "uart.h"       /* print_uart, print_uart_dec (replaces printf on CVA6) */

/* Each phase can be disabled individually via -DRUN_KEYGEN=0 / -DRUN_SIGN=0 /
 * -DRUN_VERIFY=0 (see run.sh's keygen/sign/verify arguments) to isolate its
 * cycle count. A disabled phase is skipped entirely (not even untimed) --
 * crypto_sign_keypair()/crypto_sign() take their randomness as an explicit
 * per-KAT-vector argument here (TVEC_KEYPAIR_RND/TVEC_SIGN_RND), not from a
 * persistent DRBG, so there is no state to advance by calling them; the
 * KAT's own pk/sk/sm values are loaded directly instead. */
#ifndef RUN_KEYGEN
#define RUN_KEYGEN  1
#endif
#ifndef RUN_SIGN
#define RUN_SIGN    1
#endif
#ifndef RUN_VERIFY
#define RUN_VERIFY  1
#endif

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
        memcpy(m, TVEC_IN_M_SIGN[i], MLEN_KAT);

#if RUN_KEYGEN
        write_csr(mcycle, 0);
        crypto_sign_keypair(pk, sk, TVEC_KEYPAIR_RND[i]);
        cycles = (unsigned int)read_csr(mcycle);
        print_cycles("keygen", cycles);

        if (memcmp(pk, TVEC_OUT_PK[i], CRYPTO_PUBLICKEYBYTES)) {
            fails++;
        }
        if (memcmp(sk, TVEC_OUT_SK[i], CRYPTO_SECRETKEYBYTES)) {
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
            fails++;
        }
#endif /* RUN_VERIFY */
    }

    return fails != 0;
}
