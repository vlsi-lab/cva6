/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Auth: Alessandra Dolmeta, Valeria Piscopo - Politecnico di Torino               //
// Date: June 2025                                                                 //
// Desc: Entry point for cycle-accurate profiling of HAWK-1024 on CVA6.           //
//       Uses RISC-V mcycle CSR (via encoding.h macros) to measure only the       //
//       phases that are enabled: TEST_KEY / TEST_SIGN / TEST_SIGN_OPEN.          //
//       When a phase flag is 0 its function still executes (needed for correct   //
//       DRBG state), but no cycle counter is started and nothing is printed.     //
//       KAT correctness is verified for every enabled phase.                     //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "api.h"
#include "rng.h"
#include "test_vectors_1024.h"

#include "encoding.h"   /* read_csr / write_csr / clear_csr for mcycle         */
#include "uart.h"       /* print_uart, print_uart_dec (replaces printf on CVA6) */

/* Default: keygen disabled (too costly); sign+verify enabled. Override with -DTEST_KEY=1. */
#ifndef TEST_KEY
#define TEST_KEY       1
#endif
#ifndef TEST_SIGN
#define TEST_SIGN      1
#endif
#ifndef TEST_SIGN_OPEN
#define TEST_SIGN_OPEN 1
#endif

#ifndef NTESTS
#define NTESTS 1
#else
#if (NTESTS > N_TVEC)
#error "NTESTS must be <= N_TVEC"
#endif
#endif

/* ------------------------------------------------------------------ */
/* Helpers                                                              */
/* ------------------------------------------------------------------ */

static void print_cycles(const char *label, unsigned int cyc)
{
    print_uart("Clock cycles [");
    print_uart(label);
    print_uart("]: ");
    print_uart_dec(cyc);
    print_uart("\n");
}

/*
 * Hardware-dispatch cycle accounting (ng_mp31.c/ng_fxp.c/hawk_vrfy.c) --
 * see NTT_ACCEL_DESIGN.md. Answers "how much of KeyGen/Verify is actually
 * NTT/FFT hardware-call time" directly, same pattern as hawk-256-keccak
 * (now hawk1024-opt's own KeyGen/Verify code was ported from).
 */
extern uint64_t ntt_dispatch_cycles;
extern uint64_t ntt_dispatch_calls;
extern uint64_t fft_dispatch_cycles;
extern uint64_t fft_dispatch_calls;
extern uint64_t vrfy_ntt_dispatch_cycles;
extern uint64_t vrfy_ntt_dispatch_calls;

static void print_ntt_stats_lbl(const char *label, const char *call_label,
    unsigned int phase_cycles, uint64_t ntt_cycles, uint64_t ntt_calls)
{
    unsigned int pct_x10 = phase_cycles
        ? (unsigned int)((ntt_cycles * 1000ULL) / phase_cycles) : 0;

    print_uart("  ");
    print_uart(label);
    print_uart(": ");
    print_uart_dec((int)ntt_calls);
    print_uart(" ");
    print_uart(call_label);
    print_uart(" calls, ");
    print_uart_dec((int)ntt_cycles);
    print_uart(" cycles (");
    print_uart_dec((int)(pct_x10 / 10));
    print_uart(".");
    print_uart_dec((int)(pct_x10 % 10));
    print_uart("% of phase)\n");
}

static void print_ntt_stats(const char *label, unsigned int phase_cycles,
    uint64_t ntt_cycles, uint64_t ntt_calls)
{
    print_ntt_stats_lbl(label, "mp_NTT/mp_iNTT", phase_cycles, ntt_cycles, ntt_calls);
}

#if PRINT_VECT
static void printVect(const char *name, const uint8_t *buf, size_t size)
{
    print_uart(name);
    for (size_t i = 0; i < size; i++)
        print_uart_hex8(buf[i]);
    print_uart("\n");
}
#endif

/* ------------------------------------------------------------------ */
/* Main                                                                 */
/* ------------------------------------------------------------------ */

int main(void)
{
    static unsigned char sk[CRYPTO_SECRETKEYBYTES];
    static unsigned char pk[CRYPTO_PUBLICKEYBYTES];

    static unsigned char m[MLEN_KAT];
    static unsigned char sm[SMLEN_KAT];
    static unsigned char m1[SMLEN_KAT];

    unsigned long long smlen, mlen1;
    unsigned int cycles;
    int r;

    /* Enable the hardware cycle counter (clear bit-0 of mcountinhibit) */
    clear_csr(mcountinhibit, 1);

    print_uart("Started ");
    print_uart_dec(NTESTS);
    print_uart(" test(s) - " CRYPTO_ALGNAME "\n");

    for (int i = 0; i < NTESTS; i++) {

        print_uart("Test ");
        print_uart_dec(i);
        print_uart(":\n");

        /*
         * Re-seed the NIST DRBG with the KAT seed once per test case.
         * Both keygen and sign draw from this shared DRBG state, in the
         * same order as the reference PQCgenKAT_sign.c program.
         */
        randombytes_init((unsigned char *)TVEC_SEED[i], NULL, 256);

        //*************************************************************
        // KEYGEN
        // When TEST_KEY=1 : time the call, print cycles, verify KAT.
        // When TEST_KEY=0 : call without timing (advances DRBG state);
        //                   overwrite pk/sk with TV values afterwards
        //                   so that sign/verify use the reference keys.
        //*************************************************************
#if TEST_KEY
        ntt_dispatch_cycles = 0;
        ntt_dispatch_calls  = 0;
        fft_dispatch_cycles = 0;
        fft_dispatch_calls  = 0;
        write_csr(mcycle, 0);
        r = crypto_sign_keypair(pk, sk);
        cycles = (unsigned int)read_csr(mcycle);

        if (r != 0) { print_uart("ERROR: crypto_sign_keypair\n"); return -1; }
        print_cycles("keygen", cycles);

        if (memcmp(pk, TVEC_PK[i], CRYPTO_PUBLICKEYBYTES)) { print_uart("ERROR: PK mismatch\n"); return -1; }
        if (memcmp(sk, TVEC_SK[i], CRYPTO_SECRETKEYBYTES)) { print_uart("ERROR: SK mismatch\n"); return -1; }
        print_uart("Keygen OK\n");
        print_ntt_stats("KeyGen", cycles, ntt_dispatch_cycles, ntt_dispatch_calls);
        print_ntt_stats_lbl("KeyGen (FFT)", "vect_FFT/vect_iFFT", cycles, fft_dispatch_cycles, fft_dispatch_calls);
#else
        r = crypto_sign_keypair(pk, sk);   /* advance DRBG – result discarded */
        if (r != 0) { print_uart("ERROR: crypto_sign_keypair\n"); return -1; }
        memcpy(pk, TVEC_PK[i], CRYPTO_PUBLICKEYBYTES);
        memcpy(sk, TVEC_SK[i], CRYPTO_SECRETKEYBYTES);
#endif /* TEST_KEY */

        //*************************************************************
        // SIGN
        // When TEST_SIGN=1 : time the call, print cycles, verify KAT.
        // When TEST_SIGN=0 : load TV signed message for verify below.
        //*************************************************************
#if TEST_SIGN
        memcpy(m, TVEC_MSG[i], MLEN_KAT);

        write_csr(mcycle, 0);
        r = crypto_sign(sm, &smlen, m, MLEN_KAT, sk);
        cycles = (unsigned int)read_csr(mcycle);

        if (r != 0) { print_uart("ERROR: crypto_sign\n"); return -1; }
        print_cycles("sign", cycles);

        if (smlen != (unsigned long long)SMLEN_KAT) { print_uart("ERROR: smlen mismatch\n"); return -1; }
        if (memcmp(sm, TVEC_SM[i], SMLEN_KAT))      { print_uart("ERROR: SM mismatch\n");   return -1; }
        print_uart("Sign OK\n");
#else
        memcpy(sm, TVEC_SM[i], SMLEN_KAT);
        smlen = SMLEN_KAT;
#endif /* TEST_SIGN */

        //*************************************************************
        // SIGN_OPEN (verify)
        // When TEST_SIGN_OPEN=1 : time the call, print cycles, verify.
        // When TEST_SIGN_OPEN=0 : skip entirely.
        //*************************************************************
#if TEST_SIGN_OPEN
        vrfy_ntt_dispatch_cycles = 0;
        vrfy_ntt_dispatch_calls  = 0;
        write_csr(mcycle, 0);
        r = crypto_sign_open(m1, &mlen1, sm, smlen, pk);
        cycles = (unsigned int)read_csr(mcycle);

        if (r != 0) { print_uart("ERROR: crypto_sign_open\n"); return -1; }
        print_cycles("verify", cycles);

        if (mlen1 != (unsigned long long)MLEN_KAT)  { print_uart("ERROR: mlen mismatch\n");         return -1; }
        if (memcmp(m1, TVEC_MSG[i], MLEN_KAT))      { print_uart("ERROR: msg mismatch\n"); return -1; }
        print_uart("Verify OK\n");
        print_ntt_stats("Verify", cycles, vrfy_ntt_dispatch_cycles, vrfy_ntt_dispatch_calls);
#endif /* TEST_SIGN_OPEN */

        print_uart("Test ");
        print_uart_dec(i);
        print_uart(" done\n");
    }

    print_uart("Test Successful\n");
    return 0;
}
