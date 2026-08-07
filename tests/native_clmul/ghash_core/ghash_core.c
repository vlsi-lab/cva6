// GHASH block-multiply core benchmark, native clmul/clmulh (RISC-V
// B-extension) -- same test as tests/software/ghash_core/ghash_core.c and
// tests/tightly/ghash_core/ghash_core.c (same H, A, EXPECTED[]), linking
// this tree's clmul-accelerated ghash.c instead. H is hardcoded so the
// benchmark stays scoped to exactly one GF(2^128) multiply.

#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "ghash.h"

static const uint8_t H[16] = {
    0xc6, 0xa1, 0x3b, 0x37, 0x87, 0x8f, 0x5b, 0x82, 0x6f, 0x4f, 0x81, 0x62,
    0xa1, 0xc8, 0xd8, 0x79,
};

static const uint8_t A[16] = {
    0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab,
    0xac, 0xad, 0xae, 0xaf,
};

static const uint8_t EXPECTED[16] = {
    0x2e, 0xfe, 0xa2, 0xbb, 0xd9, 0x29, 0x67, 0x24, 0x65, 0xca, 0xb7, 0x68,
    0xd8, 0x6f, 0x0b, 0xe0,
};

int main()
{
  uint8_t Z[16];
  int errors = 0;
  unsigned long cycles, instrs;

  printf("GHASH Block-Multiply Core Benchmark - Native clmul\n");

  BENCH_ENABLE();
  BENCH_START();
  gf128_mul(Z, A, H);
  BENCH_READ(cycles, instrs);

  printf("cycles=%lu instrs=%lu\n", cycles, instrs);

  for (int i = 0; i < 16; i++) {
    if (Z[i] != EXPECTED[i]) {
      printf("!!! Mismatch at byte %d: expected 0x%02x, got 0x%02x !!!\n", i, EXPECTED[i], Z[i]);
      errors++;
    }
  }

  if (errors == 0) printf("GHASH Block-Multiply Core Benchmark terminated with no errors.\n");
  else              printf("GHASH Block-Multiply Core Benchmark terminated with %d errors\n", errors);

  return errors;
}
