// Keccak sponge benchmark: shake128_absorb() alone, across the input-size
// matrix 0/32/64/128/1024/4096 bytes. Identical source on the software and
// tightly trees -- only the linked KeccakF1600_StatePermute differs.
// Correctness is checked by finishing (untimed) and comparing against the
// one-shot shake128() API, not a fixed KAT -- this benchmarks the
// incremental API's internal consistency, not a specific digest value.
//
// Note: for inputs <= SHAKE128_RATE (168 B), shake128_absorb() never calls
// the permutation internally (see fips202.c's keccak_absorb -- it only
// permutes when the running buffer fills to a full rate block), so the
// smaller sizes here isolate pure buffering/XOR cost. Larger sizes
// necessarily include one or more internal permutations -- compare against
// keccak_core's single-permutation number to see the split.
//
// A 64 KiB size point was requested but had to be dropped: this specific
// Verilator/fesvr veri-testharness build enforces a hard ~2,000,000
// simulated-core-cycle watchdog (confirmed by an actual run: the 64 KiB
// case hit "*** FAILED *** (tohost = 2147483647) after 2000013 cycles" --
// the testbench's own htif/DTM layer giving up, not a mismatch or a
// `cva6.py --iss_timeout` wall-clock issue, which was ruled out first by
// raising that timeout and re-running). 4096 B is the largest size that
// completes within that budget in this environment.

#include <string.h>
#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "fips202.h"

#define MAXLEN 4096
static uint8_t IN[MAXLEN];

static const size_t SIZES[] = {0, 32, 64, 128, 1024, 4096};
#define NSIZES (sizeof(SIZES) / sizeof(SIZES[0]))

int main()
{
  int errors = 0;
  for (size_t i = 0; i < MAXLEN; i++) IN[i] = (uint8_t)(i * 7 + 3);

  printf("Keccak Sponge Absorb-Only Benchmark - SHAKE128, input 0 B..64 KiB\n");
  BENCH_ENABLE();

  for (size_t k = 0; k < NSIZES; k++) {
    size_t n = SIZES[k];
    keccak_state st;
    unsigned long cycles, instrs;

    shake128_init(&st);
    BENCH_START();
    shake128_absorb(&st, IN, n);
    BENCH_READ(cycles, instrs);

    uint8_t got[32], want[32];
    shake128_finalize(&st);
    shake128_squeeze(got, sizeof(got), &st);
    shake128(want, sizeof(want), IN, n);
    if (memcmp(got, want, sizeof(got)) != 0) {
      printf("!!! Mismatch for input size %lu !!!\n", (unsigned long)n);
      errors++;
    }

    unsigned long bpc_e4 = n ? (8UL * n * 10000UL) / cycles : 0;
    printf("absorb size=%6lu B cycles=%8lu instrs=%8lu throughput=%lu.%04lu bits/cycle\n",
           (unsigned long)n, cycles, instrs, bpc_e4 / 10000, bpc_e4 % 10000);
  }

  if (errors == 0) printf("Keccak Sponge Absorb-Only Benchmark terminated with no errors.\n");
  else              printf("Keccak Sponge Absorb-Only Benchmark terminated with %d errors\n", errors);

  return errors;
}
