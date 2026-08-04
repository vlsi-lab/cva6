// AES-128-ECB encryption benchmark, 2 independent blocks. Identical source
// on the software and tightly trees -- only the linked aes128_block.c
// implementation differs, per run.sh. Block 0 is the standard FIPS-197
// Appendix B vector; block 1's ciphertext was computed independently via
// Python's pycryptodome (Crypto.Cipher.AES, MODE_ECB).

#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "aes128_block.h"

static const uint8_t KEY[16] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
    0x0c, 0x0d, 0x0e, 0x0f,
};

static uint8_t blocks[2][16] = {
    { 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb,
      0xcc, 0xdd, 0xee, 0xff },
    { 0x05, 0x12, 0x1f, 0x2c, 0x39, 0x46, 0x53, 0x60, 0x6d, 0x7a, 0x87, 0x94,
      0xa1, 0xae, 0xbb, 0xc8 },
};

static const uint8_t EXPECTED[2][16] = {
    { 0x69, 0xc4, 0xe0, 0xd8, 0x6a, 0x7b, 0x04, 0x30, 0xd8, 0xcd, 0xb7, 0x80,
      0x70, 0xb4, 0xc5, 0x5a },
    { 0xc3, 0xb5, 0x47, 0x32, 0x35, 0x6f, 0x7d, 0x45, 0x24, 0xde, 0xfb, 0x84,
      0x23, 0x84, 0xcf, 0x09 },
};

int main()
{
  aes128_ctx_t ctx;
  int errors = 0;
  unsigned long cycles, instrs;

  printf("AES-128-ECB Encryption Benchmark\n");

  BENCH_ENABLE();
  BENCH_START();
  aes128_key_expand(&ctx, KEY);
  aes128_encrypt_block(&ctx, blocks[0]);
  aes128_encrypt_block(&ctx, blocks[1]);
  BENCH_READ(cycles, instrs);

  printf("cycles=%lu instrs=%lu\n", cycles, instrs);

  for (int b = 0; b < 2; b++) {
    for (int i = 0; i < 16; i++) {
      if (blocks[b][i] != EXPECTED[b][i]) {
        printf("!!! Mismatch at block %d byte %d: expected 0x%02x, got 0x%02x !!!\n",
               b, i, EXPECTED[b][i], blocks[b][i]);
        errors++;
      }
    }
  }

  if (errors == 0) printf("AES-128-ECB Encryption Benchmark terminated with no errors.\n");
  else              printf("AES-128-ECB Encryption Benchmark terminated with %d errors\n", errors);

  return errors;
}
