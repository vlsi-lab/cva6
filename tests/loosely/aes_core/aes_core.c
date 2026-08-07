// AES-128 single-block encrypt benchmark, loosely-coupled AXI accelerator
// (kecc_aes_k_axi, v2 RTL), checked against the standard FIPS-197 Appendix B
// vector (the same one tests/aes64_xif_tests/aes128_full.c uses for the ISE
// coprocessor's full-cipher path):
//   key       = 000102030405060708090a0b0c0d0e0f
//   plaintext = 00112233445566778899aabbccddeeff
//   ciphertext= 69c4e0d86a7b0430d8cdb78070b4c55a
//
// Unlike tests/software/aes_core.c and tests/tightly/aes_core.c (both of
// which benchmark key expansion alone), kecc_aes_k_top's AXI register map
// only exposes the final block result -- there's no register that surfaces
// the intermediate round-key schedule -- so this test benchmarks one full
// encrypt (init + next) instead. It is intentionally not a byte-identical
// port of the other two trees' aes_core test.

#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "kecc_aes_k_axi.h"

static const uint8_t KEY[32] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
    0x0c, 0x0d, 0x0e, 0x0f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

static const uint8_t PLAINTEXT[16] = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
    0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
};

static const uint8_t EXPECTED_CIPHERTEXT[16] = {
    0x69, 0xc4, 0xe0, 0xd8, 0x6a, 0x7b, 0x04, 0x30,
    0xd8, 0xcd, 0xb7, 0x80, 0x70, 0xb4, 0xc5, 0x5a,
};

int main()
{
    uint8_t ciphertext[16];
    unsigned long cycles, instrs;
    int errors = 0;

    printf("AES-128 Single-Block Encrypt Benchmark - Loosely (kecc_aes_k_axi v2)\n");

    BENCH_ENABLE();
    BENCH_START();
    kecc_aes_k_axi_aes_encrypt_block(KEY, /*keylen256=*/0, PLAINTEXT, ciphertext);
    BENCH_READ(cycles, instrs);

    printf("cycles=%lu instrs=%lu\n", cycles, instrs);

    for (int i = 0; i < 16; i++) {
        if (ciphertext[i] != EXPECTED_CIPHERTEXT[i]) {
            printf("!!! Mismatch at byte %d: expected 0x%02x, got 0x%02x !!!\n", i, EXPECTED_CIPHERTEXT[i], ciphertext[i]);
            errors++;
        }
    }

    if (errors == 0) printf("AES-128 Single-Block Encrypt Benchmark terminated with no errors.\n");
    else              printf("AES-128 Single-Block Encrypt Benchmark terminated with %d errors\n", errors);

    return errors;
}
