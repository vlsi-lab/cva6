// SHAKE256 benchmark, long input (2048 bytes, to show cycle scaling with
// input length vs. shake128_short's 32 bytes). Identical source on the
// software and tightly trees -- only the linked fips202.c (and, on tightly,
// keccak_permute.s) differs, per run.sh. Expected output computed
// independently via Python's hashlib.shake_256.

#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "fips202.h"

#define IN_LEN 2048

static const uint8_t EXPECTED[64] = {
    0xcc, 0x57, 0x01, 0x17, 0x4f, 0x33, 0x3e, 0x9c, 0x50, 0x3b, 0x9b, 0xd9,
    0x4e, 0x91, 0x8c, 0xeb, 0x8c, 0x48, 0xf3, 0x7e, 0x5f, 0x1f, 0x1b, 0xfb,
    0x67, 0xe6, 0x07, 0x44, 0xf9, 0x80, 0x67, 0x25, 0xd2, 0x76, 0xd3, 0x3e,
    0xdc, 0xbb, 0xe3, 0xd8, 0x33, 0x2b, 0xf9, 0x4f, 0xcf, 0x8d, 0xf6, 0xd8,
    0x51, 0xba, 0xd3, 0x82, 0x93, 0x52, 0x27, 0xc3, 0x8c, 0x2a, 0x3c, 0xef,
    0x16, 0xd0, 0x76, 0x99,
};

int main()
{
  static uint8_t in[IN_LEN];
  uint8_t out[64];
  int errors = 0;
  unsigned long cycles, instrs;

  // in[i] = (i*31 + 17) % 256 -- matches the Python reference exactly.
  for (int i = 0; i < IN_LEN; i++)
    in[i] = (uint8_t)((i * 31 + 17) % 256);

  printf("SHAKE256 Benchmark - long input (%d bytes)\n", IN_LEN);

  BENCH_ENABLE();
  BENCH_START();
  shake256(out, sizeof(out), in, IN_LEN);
  BENCH_READ(cycles, instrs);

  printf("cycles=%lu instrs=%lu\n", cycles, instrs);

  for (int i = 0; i < 64; i++) {
    if (out[i] != EXPECTED[i]) {
      printf("!!! Mismatch at byte %d: expected 0x%02x, got 0x%02x !!!\n", i, EXPECTED[i], out[i]);
      errors++;
    }
  }

  if (errors == 0) printf("SHAKE256 Benchmark terminated with no errors.\n");
  else              printf("SHAKE256 Benchmark terminated with %d errors\n", errors);

  return errors;
}
