// Keccak sponge benchmark: multiple incremental shake128_squeeze() calls
// (64-byte chunks) vs. a single monolithic call over the same total output,
// for representative sizes 1024 and 4096, both starting from the same
// finalized state. Checked against each other and against the one-shot
// shake128() API. Identical source on the software and tightly trees.

#include <string.h>
#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "fips202.h"

#define MSGLEN 64
static uint8_t MSG[MSGLEN];

static const size_t TOTALS[] = {1024, 4096};
#define NTOTALS (sizeof(TOTALS) / sizeof(TOTALS[0]))
#define CHUNK 64
#define MAXOUT 4096

static uint8_t out_mono[MAXOUT], out_chunk[MAXOUT], want[MAXOUT];

int main()
{
  int errors = 0;
  for (int i = 0; i < MSGLEN; i++) MSG[i] = (uint8_t)(i * 23 + 4);

  keccak_state finalized;
  shake128_init(&finalized);
  shake128_absorb(&finalized, MSG, MSGLEN);
  shake128_finalize(&finalized); // untimed -- shared starting point

  printf("Keccak Sponge Incremental-Squeeze Benchmark - SHAKE128, monolithic vs %d-byte chunks\n", CHUNK);
  BENCH_ENABLE();

  for (size_t k = 0; k < NTOTALS; k++) {
    size_t n = TOTALS[k];
    keccak_state st_mono = finalized, st_chunk = finalized;
    unsigned long mono_cycles, mono_instrs, chunk_cycles, chunk_instrs;

    BENCH_START();
    shake128_squeeze(out_mono, n, &st_mono);
    BENCH_READ(mono_cycles, mono_instrs);

    BENCH_START();
    for (size_t off = 0; off < n; off += CHUNK) {
      size_t c = (n - off < CHUNK) ? (n - off) : CHUNK;
      shake128_squeeze(out_chunk + off, c, &st_chunk);
    }
    BENCH_READ(chunk_cycles, chunk_instrs);

    shake128(want, n, MSG, MSGLEN);
    if (memcmp(out_mono, want, n) != 0 || memcmp(out_chunk, want, n) != 0) {
      printf("!!! Mismatch for output size %lu (monolithic or chunked disagrees with one-shot) !!!\n",
             (unsigned long)n);
      errors++;
    }

    printf("size=%6lu B monolithic cycles=%8lu instrs=%8lu, %d-byte-chunked cycles=%8lu instrs=%8lu "
           "(chunking overhead: %ld cycles, %ld instrs)\n",
           (unsigned long)n, mono_cycles, mono_instrs, CHUNK, chunk_cycles, chunk_instrs,
           (long)chunk_cycles - (long)mono_cycles, (long)chunk_instrs - (long)mono_instrs);
  }

  if (errors == 0) printf("Keccak Sponge Incremental-Squeeze Benchmark terminated with no errors.\n");
  else              printf("Keccak Sponge Incremental-Squeeze Benchmark terminated with %d errors\n", errors);

  return errors;
}
