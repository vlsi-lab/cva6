// Keccak sponge benchmark: shake128_init() alone -- state zeroing cost.
// Identical source on the software and tightly trees (only the linked
// KeccakF1600_StatePermute differs, and init doesn't call it at all).
//
// Part of the systematic sponge-interface suite (see result.md): FIPS 203
// defines separate init/absorb/squeeze operations for SHAKE128 because
// ML-KEM/ML-DSA drive it incrementally, not via one-shot calls -- this
// suite measures each phase on its own instead of only the one-shot API.

#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "fips202.h"

int main()
{
  keccak_state st;
  int errors = 0;
  unsigned long cycles, instrs;

  printf("Keccak Sponge Init Benchmark - SHAKE128\n");

  BENCH_ENABLE();
  BENCH_START();
  shake128_init(&st);
  BENCH_READ(cycles, instrs);

  for (int i = 0; i < 25; i++) {
    if (st.s[i] != 0) {
      printf("!!! State word %d not zeroed after init !!!\n", i);
      errors++;
    }
  }
  if (st.pos != 0) {
    printf("!!! pos not zeroed after init (got %u) !!!\n", st.pos);
    errors++;
  }

  printf("init cycles=%lu instrs=%lu (throughput: N/A -- no data processed)\n", cycles, instrs);

  if (errors == 0) printf("Keccak Sponge Init Benchmark terminated with no errors.\n");
  else              printf("Keccak Sponge Init Benchmark terminated with %d errors\n", errors);

  return errors;
}
