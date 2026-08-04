// Keccak sponge benchmark: shake128_squeeze() alone, across the output-size
// matrix 32/64/128/512/1024/2048/4096 bytes, all starting from the same
// finalized state (a fixed 64-byte message, absorbed+finalized once,
// untimed). Identical source on the software and tightly trees. Checked
// against the one-shot shake128() API.

#include <string.h>
#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "fips202.h"

#define MSGLEN 64
static uint8_t MSG[MSGLEN];

static const size_t SIZES[] = {32, 64, 128, 512, 1024, 2048, 4096};
#define NSIZES (sizeof(SIZES) / sizeof(SIZES[0]))
#define MAXOUT 4096

static uint8_t out[MAXOUT], want[MAXOUT];

int main()
{
  int errors = 0;
  for (int i = 0; i < MSGLEN; i++) MSG[i] = (uint8_t)(i * 11 + 5);

  keccak_state finalized;
  shake128_init(&finalized);
  shake128_absorb(&finalized, MSG, MSGLEN);
  shake128_finalize(&finalized); // untimed -- shared starting point for every size below

  printf("Keccak Sponge Squeeze-Only Benchmark - SHAKE128, output 32 B..4 KiB\n");
  BENCH_ENABLE();

  for (size_t k = 0; k < NSIZES; k++) {
    size_t n = SIZES[k];
    keccak_state st = finalized; // restore the pristine post-finalize state each time
    unsigned long cycles, instrs;

    BENCH_START();
    shake128_squeeze(out, n, &st);
    BENCH_READ(cycles, instrs);

    shake128(want, n, MSG, MSGLEN);
    if (memcmp(out, want, n) != 0) {
      printf("!!! Mismatch for output size %lu !!!\n", (unsigned long)n);
      errors++;
    }

    unsigned long bpc_e4 = (8UL * n * 10000UL) / cycles;
    printf("squeeze size=%6lu B cycles=%8lu instrs=%8lu throughput=%lu.%04lu bits/cycle\n",
           (unsigned long)n, cycles, instrs, bpc_e4 / 10000, bpc_e4 % 10000);
  }

  if (errors == 0) printf("Keccak Sponge Squeeze-Only Benchmark terminated with no errors.\n");
  else              printf("Keccak Sponge Squeeze-Only Benchmark terminated with %d errors\n", errors);

  return errors;
}
