// AES-128 key expansion core benchmark, coprocessor-accelerated (aes64ks1i/
// aes64ks2) -- the AES analogue of keccak_core's single permutation call.
// Expected round keys are the same FIPS-197 Appendix A.1 example as the
// software side's aes_core test, re-expressed as little-endian 64-bit
// halves (matching how `ld` loads the key bytes) -- already validated
// against FIPS-197 encryption end-to-end in tests/aes64_xif_tests/aes128_full.c.

#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "aes128_block.h"

static const uint8_t KEY[16] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
    0x0c, 0x0d, 0x0e, 0x0f,
};

static const uint64_t EXPECTED[22] = {
    0x0706050403020100ULL, 0x0f0e0d0c0b0a0908ULL,
    0xfa72afd2fd74aad6ULL, 0xfe76abd6f178a6daULL,
    0xf1bd3d640bcf92b6ULL, 0xfeb3306800c59bbeULL,
    0xbfc9c2d24e74ffb6ULL, 0x41bf6904bf0c596cULL,
    0x033e3595bcf7f747ULL, 0xfd8d05fdbc326cf9ULL,
    0xeb9d9fa9e8a3aa3cULL, 0xaa22f6ad57aff350ULL,
    0x9692a6f77d0f395eULL, 0x6b1fa30ac13d55a7ULL,
    0x8ce25fe31a70f914ULL, 0x26c0a94e4ddf0a44ULL,
    0xb9651ca435874347ULL, 0xd27abfaef4ba16e0ULL,
    0x685785f0d1329954ULL, 0x4e972cbe9ced9310ULL,
    0x174a94e37f1d1113ULL, 0xc5302b4d8ba707f3ULL,
};

int main()
{
  aes128_ctx_t ctx;
  int errors = 0;
  unsigned long cycles, instrs;

  printf("AES-128 Key Expansion Core Benchmark - Tightly (coprocessor)\n");

  BENCH_ENABLE();
  BENCH_START();
  aes128_key_expand(&ctx, KEY);
  BENCH_READ(cycles, instrs);

  printf("cycles=%lu instrs=%lu\n", cycles, instrs);

  for (int i = 0; i < 22; i++) {
    if (ctx.enc_rk[i] != EXPECTED[i]) {
      printf("!!! Mismatch at enc_rk[%d]: expected 0x%016llx, got 0x%016llx !!!\n", i, EXPECTED[i], ctx.enc_rk[i]);
      errors++;
    }
  }

  if (errors == 0) printf("AES-128 Key Expansion Core Benchmark terminated with no errors.\n");
  else              printf("AES-128 Key Expansion Core Benchmark terminated with %d errors\n", errors);

  return errors;
}
