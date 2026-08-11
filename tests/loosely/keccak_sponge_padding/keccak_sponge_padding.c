// Keccak sponge benchmark: shake128_finalize() alone -- the padding /
// domain-separation step. Identical source on the software and tightly
// trees. Per fips202.c's keccak_finalize(), this is just two XORs (the
// domain-separator byte and the top pad bit) at the current buffer
// position -- O(1), not proportional to any data size. The permutation
// that actually closes the absorb phase is deferred to the *first*
// squeeze call (see keccak_squeeze's `if (pos == r) permute` check), so
// it is deliberately NOT included here -- it's covered by
// keccak_sponge_squeeze's numbers instead.

#include <string.h>
#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "fips202.h"

#define MSGLEN 64
static uint8_t MSG[MSGLEN];

int main()
{
  int errors = 0;
  for (int i = 0; i < MSGLEN; i++) MSG[i] = (uint8_t)(i * 13 + 1);

  keccak_state st;
  shake128_init(&st);
  shake128_absorb(&st, MSG, MSGLEN); // untimed

  printf("Keccak Sponge Padding/Domain-Separation Benchmark - SHAKE128\n");
  printf("(finalize() only applies the pad bit + domain separator -- the\n"
         " state-closing permutation is deferred to the first squeeze call,\n"
         " measured separately by keccak_sponge_squeeze.)\n");

  BENCH_ENABLE();
  unsigned long cycles, instrs;
  BENCH_START();
  shake128_finalize(&st);
  BENCH_READ(cycles, instrs);

  uint8_t got[32], want[32];
  shake128_squeeze(got, sizeof(got), &st);
  shake128(want, sizeof(want), MSG, MSGLEN);
  if (memcmp(got, want, sizeof(got)) != 0) {
    printf("!!! Mismatch after finalize+squeeze !!!\n");
    errors++;
  }

  printf("finalize cycles=%lu instrs=%lu (throughput: N/A -- O(1) padding op, not data-proportional)\n",
         cycles, instrs);

  if (errors == 0) printf("Keccak Sponge Padding Benchmark terminated with no errors.\n");
  else              printf("Keccak Sponge Padding Benchmark terminated with %d errors\n", errors);

  return errors;
}
