// SHAKE128 benchmark, short input (32 bytes). Identical source on the
// software and tightly trees -- only the linked fips202.c (and, on tightly,
// keccak_permute.s) differs, per run.sh. Expected output computed
// independently via Python's hashlib.shake_128.

#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "fips202.h"

static const uint8_t IN[32] = {
    0x03, 0x0a, 0x11, 0x18, 0x1f, 0x26, 0x2d, 0x34, 0x3b, 0x42, 0x49, 0x50,
    0x57, 0x5e, 0x65, 0x6c, 0x73, 0x7a, 0x81, 0x88, 0x8f, 0x96, 0x9d, 0xa4,
    0xab, 0xb2, 0xb9, 0xc0, 0xc7, 0xce, 0xd5, 0xdc,
};

static const uint8_t EXPECTED[32] = {
    0x99, 0x9c, 0xb4, 0x69, 0xc5, 0x7a, 0x78, 0x9e, 0x7e, 0x9e, 0xad, 0x11,
    0x72, 0xc2, 0xf6, 0x86, 0x63, 0xe0, 0xad, 0xc9, 0x97, 0xeb, 0xf1, 0x51,
    0xf4, 0x20, 0x01, 0x8c, 0x20, 0x2e, 0x7d, 0x65,
};

int main()
{
  uint8_t out[32];
  int errors = 0;
  unsigned long cycles, instrs;

  printf("SHAKE128 Benchmark - short input (%d bytes)\n", (int)sizeof(IN));

  BENCH_ENABLE();
  BENCH_START();
  shake128(out, sizeof(out), IN, sizeof(IN));
  BENCH_READ(cycles, instrs);

  printf("cycles=%lu instrs=%lu\n", cycles, instrs);

  for (int i = 0; i < 32; i++) {
    if (out[i] != EXPECTED[i]) {
      printf("!!! Mismatch at byte %d: expected 0x%02x, got 0x%02x !!!\n", i, EXPECTED[i], out[i]);
      errors++;
    }
  }

  if (errors == 0) printf("SHAKE128 Benchmark terminated with no errors.\n");
  else              printf("SHAKE128 Benchmark terminated with %d errors\n", errors);

  return errors;
}
