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

/*
 * Hardware-dispatch cycle accounting (vrfy.c's mq_NTT_hw()/mq_iNTT_hw()) --
 * answers "how much of Verify is actually NTT/iNTT hardware-call time",
 * same pattern as tests/hawk1024-opt/main.c's ntt_dispatch_cycles.
 */
extern uint64_t falcon_ntt_dispatch_cycles;
extern uint64_t falcon_ntt_dispatch_calls;

/*
 * Same accounting for Zf(hash_to_point_vartime)()/Zf(is_short)() (common.c)
 * -- isolates the rejection-sampling loop's and the norm-bound check's
 * share of Verify, i.e. the two functions HAWK_FALCON_VERIFY_HW_ACCELERATION.md
 * checklist items #4/#5 propose dedicated hardware for.
 */
extern uint64_t falcon_hash_to_point_cycles;
extern uint64_t falcon_hash_to_point_calls;
extern uint64_t falcon_is_short_cycles;
extern uint64_t falcon_is_short_calls;

static void print_ntt_stats(const char *label, const char *unit,
    unsigned int phase_cycles, uint64_t sub_cycles, uint64_t sub_calls)
{
    unsigned int pct_x10 = phase_cycles
        ? (unsigned int)((sub_cycles * 1000ULL) / phase_cycles) : 0;

    print_uart("  ");
    print_uart(label);
    print_uart(": ");
    print_uart_dec((int)sub_calls);
    print_uart(" ");
    print_uart(unit);
    print_uart(" calls, ");
    print_uart_dec((int)sub_cycles);
    print_uart(" cycles (");
    print_uart_dec((int)(pct_x10 / 10));
    print_uart(".");
    print_uart_dec((int)(pct_x10 % 10));
    print_uart("% of phase)\n");
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
        falcon_ntt_dispatch_cycles   = 0;
        falcon_ntt_dispatch_calls    = 0;
        falcon_hash_to_point_cycles  = 0;
        falcon_hash_to_point_calls   = 0;
        falcon_is_short_cycles       = 0;
        falcon_is_short_calls        = 0;
        write_csr(mcycle, 0);
        crypto_sign_open(m1, &mlen1, sm, smlen, pk);
        cycles = (unsigned int)read_csr(mcycle);
        print_cycles("verify", cycles);
        print_ntt_stats("Verify NTT/iNTT", "mq_NTT_hw/mq_iNTT_hw",
            cycles, falcon_ntt_dispatch_cycles, falcon_ntt_dispatch_calls);
        print_ntt_stats("Verify hash-to-point", "hash_to_point_vartime",
            cycles, falcon_hash_to_point_cycles, falcon_hash_to_point_calls);
        print_ntt_stats("Verify is_short", "is_short",
            cycles, falcon_is_short_cycles, falcon_is_short_calls);

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
