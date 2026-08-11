// Keccak sponge benchmark: multiple incremental shake128_absorb() calls
// (64-byte chunks) vs. a single monolithic call over the same total bytes,
// for representative sizes 1024 and 4096. Both are checked against each
// other and against the one-shot shake128() API -- proves the incremental
// API composes correctly across call boundaries, which is exactly what
// ML-KEM/ML-DSA rely on when feeding SHAKE128 incrementally rather than in
// one shot. Identical source on the software and tightly trees.

#include <string.h>
#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "fips202.h"

#define MAXLEN 4096
static uint8_t IN[MAXLEN];

static const size_t TOTALS[] = {1024, 4096};
#define NTOTALS (sizeof(TOTALS) / sizeof(TOTALS[0]))
#define CHUNK 64

int main()
{
  int errors = 0;
  for (size_t i = 0; i < MAXLEN; i++) IN[i] = (uint8_t)(i * 19 + 2);

  printf("Keccak Sponge Incremental-Absorb Benchmark - SHAKE128, monolithic vs %d-byte chunks\n", CHUNK);
  BENCH_ENABLE();

  for (size_t k = 0; k < NTOTALS; k++) {
    size_t n = TOTALS[k];
    keccak_state st_mono, st_chunk;
    unsigned long mono_cycles, mono_instrs, chunk_cycles, chunk_instrs;

    shake128_init(&st_mono);
    BENCH_START();
    shake128_absorb(&st_mono, IN, n);
    BENCH_READ(mono_cycles, mono_instrs);

    shake128_init(&st_chunk);
    BENCH_START();
    for (size_t off = 0; off < n; off += CHUNK) {
      size_t c = (n - off < CHUNK) ? (n - off) : CHUNK;
      shake128_absorb(&st_chunk, IN + off, c);
    }
    BENCH_READ(chunk_cycles, chunk_instrs);

    uint8_t got_mono[32], got_chunk[32], want[32];
    shake128_finalize(&st_mono);
    shake128_squeeze(got_mono, sizeof(got_mono), &st_mono);
    shake128_finalize(&st_chunk);
    shake128_squeeze(got_chunk, sizeof(got_chunk), &st_chunk);
    shake128(want, sizeof(want), IN, n);
    if (memcmp(got_mono, want, sizeof(want)) != 0 || memcmp(got_chunk, want, sizeof(want)) != 0) {
      printf("!!! Mismatch for total size %lu (monolithic or chunked disagrees with one-shot) !!!\n",
             (unsigned long)n);
      errors++;
    }

    printf("size=%6lu B monolithic cycles=%8lu instrs=%8lu, %d-byte-chunked cycles=%8lu instrs=%8lu "
           "(chunking overhead: %ld cycles, %ld instrs)\n",
           (unsigned long)n, mono_cycles, mono_instrs, CHUNK, chunk_cycles, chunk_instrs,
           (long)chunk_cycles - (long)mono_cycles, (long)chunk_instrs - (long)mono_instrs);
  }

  if (errors == 0) printf("Keccak Sponge Incremental-Absorb Benchmark terminated with no errors.\n");
  else              printf("Keccak Sponge Incremental-Absorb Benchmark terminated with %d errors\n", errors);

  return errors;
}
