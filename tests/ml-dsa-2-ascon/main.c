///////////////////////////////////////////////////////////////////////////////////////
//                                                                                   //
// Desc: Entry point for testing the ML-DSA (Dilithium-2) implementation (Ascon     //
//       symmetric primitives) on cva6. Runs keygen/sign/verify and reports         //
//       per-phase cycle counts, mirroring tests/ml-kem-512-ascon/main.c.           //
//                                                                                   //
///////////////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "sign.h"
#include "params.h"
#include "randombytes.h"
#include "encoding.h"
#include "uart.h"

#define TEST_KEY    1
#define TEST_SIGN   1
#define TEST_VERIFY 1

#define MLEN  59
#define CTXLEN 14

static uint8_t pk[CRYPTO_PUBLICKEYBYTES];
static uint8_t sk[CRYPTO_SECRETKEYBYTES];
static uint8_t sig[CRYPTO_BYTES];
static uint8_t m[MLEN];
static uint8_t ctx[CTXLEN];

void printVect(char* name, uint8_t* buf, size_t size) {
    print_uart(name);
    for (size_t i = 0; i < size; i++){
        print_uart_hex8(buf[i]);
    }
    print_uart("\n");
}

int main(void)
{
    unsigned int cycles;
    size_t siglen;
    int ret = -1;

    memcpy(ctx, "test_dilithium", CTXLEN);
    randombytes(m, MLEN);

    //*************************************************
    // KEYGEN
    //*************************************************
    #if TEST_KEY
        clear_csr(mcountinhibit, 1);
        write_csr(mcycle, 0);

        crypto_sign_keypair(pk, sk);

        cycles = read_csr(mcycle);
        print_uart("Number of clock cycles for crypto_sign_keypair: ");
        print_uart_dec(cycles);
        print_uart("\n");
    #endif /* TEST_KEY */

    //*************************************************
    // SIGN
    //*************************************************
    #if TEST_SIGN
        write_csr(mcycle, 0);

        crypto_sign_signature(sig, &siglen, m, MLEN, ctx, CTXLEN, sk);

        cycles = read_csr(mcycle);
        print_uart("Number of clock cycles for crypto_sign_signature: ");
        print_uart_dec(cycles);
        print_uart("\n");

        if (siglen != CRYPTO_BYTES) { print_uart("ERROR: signature length mismatch\n"); }
    #endif /* TEST_SIGN */

    //*************************************************
    // VERIFY
    //*************************************************
    #if TEST_VERIFY
        write_csr(mcycle, 0);

        ret = crypto_sign_verify(sig, siglen, m, MLEN, ctx, CTXLEN, pk);

        cycles = read_csr(mcycle);
        print_uart("Number of clock cycles for crypto_sign_verify: ");
        print_uart_dec(cycles);
        print_uart("\n");

        if (ret) { print_uart("ERROR: signature verification failed\n"); }
    #endif /* TEST_VERIFY */

    printVect("pk= ", pk, CRYPTO_PUBLICKEYBYTES);
    printVect("sig= ", sig, CRYPTO_BYTES);

    if (ret == 0) print_uart("Test Successful\n");
    else          print_uart("Test Failed\n");

    return ret;
}
