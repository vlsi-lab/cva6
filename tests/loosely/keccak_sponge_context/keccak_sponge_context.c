// Keccak sponge benchmark: context save/restore, i.e. the cost of parking
// an in-flight (partially absorbed) keccak_state and resuming it later --
// relevant whenever incremental SHAKE calls are interleaved with other
// work (e.g. ML-KEM/ML-DSA), rather than run start-to-finish uninterrupted.
// Identical source on the software and tightly trees.

#include <string.h>
#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "fips202.h"

#define MSGLEN 128
static uint8_t MSG[MSGLEN];

int main()
{
  int errors = 0;
  for (int i = 0; i < MSGLEN; i++) MSG[i] = (uint8_t)(i * 17 + 9);

  keccak_state st, saved;
  shake128_init(&st);
  shake128_absorb(&st, MSG, MSGLEN / 2); // untimed: absorb half, leaving a genuinely mid-stream state

  printf("Keccak Sponge Context Save/Restore Benchmark - SHAKE128 (sizeof(keccak_state)=%lu bytes)\n",
         (unsigned long)sizeof(keccak_state));
  BENCH_ENABLE();

  unsigned long save_cycles, save_instrs, restore_cycles, restore_instrs;

  BENCH_START();
  memcpy(&saved, &st, sizeof(saved));
  BENCH_READ(save_cycles, save_instrs);

  // Simulate the live state having been evicted while something else ran
  // in its place, so the restore below is a real, necessary step, not a
  // no-op the compiler could have elided.
  memset(&st, 0xFF, sizeof(st));

  BENCH_START();
  memcpy(&st, &saved, sizeof(st));
  BENCH_READ(restore_cycles, restore_instrs);

  // Resume: finish absorbing the second half, finalize, squeeze, and check
  // against the one-shot API over the whole message -- proves save/restore
  // didn't corrupt the in-flight sponge state.
  shake128_absorb(&st, MSG + MSGLEN / 2, MSGLEN - MSGLEN / 2);
  shake128_finalize(&st);
  uint8_t got[32], want[32];
  shake128_squeeze(got, sizeof(got), &st);
  shake128(want, sizeof(want), MSG, MSGLEN);
  if (memcmp(got, want, sizeof(got)) != 0) {
    printf("!!! Mismatch after save/restore + resumed absorb !!!\n");
    errors++;
  }

  printf("save cycles=%lu instrs=%lu, restore cycles=%lu instrs=%lu\n",
         save_cycles, save_instrs, restore_cycles, restore_instrs);

  if (errors == 0) printf("Keccak Sponge Context Benchmark terminated with no errors.\n");
  else              printf("Keccak Sponge Context Benchmark terminated with %d errors\n", errors);

  return errors;
}
