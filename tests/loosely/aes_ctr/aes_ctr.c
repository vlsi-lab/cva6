// AES-128-CTR benchmark, 40 bytes (2 full blocks + an 8-byte partial block,
// to exercise the non-block-multiple path). Checked against ciphertext
// independently computed via Python pycryptodome (Crypto.Cipher.AES,
// MODE_CTR, nonce=b'', initial_value=COUNTER). Identical source on the
// software and tightly trees -- only the linked aes128_block.c
// implementation differs, per run.sh.
//
// Simple, streaming, parallelizable, and useful for separating raw AES-core
// performance from authentication overhead (compare against aes_gcm, which
// layers GHASH authentication on top of the same kind of keystream).

#include <string.h>
#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "aes_ctr.h"

static const uint8_t KEY[16] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
    0x0c, 0x0d, 0x0e, 0x0f,
};

static const uint8_t COUNTER[16] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
    0x0c, 0x0d, 0x0e, 0x0f,
};

static const uint8_t PT[40] = {
    0x01, 0x04, 0x07, 0x0a, 0x0d, 0x10, 0x13, 0x16, 0x19, 0x1c, 0x1f, 0x22,
    0x25, 0x28, 0x2b, 0x2e, 0x31, 0x34, 0x37, 0x3a, 0x3d, 0x40, 0x43, 0x46,
    0x49, 0x4c, 0x4f, 0x52, 0x55, 0x58, 0x5b, 0x5e, 0x61, 0x64, 0x67, 0x6a,
    0x6d, 0x70, 0x73, 0x76,
};

static const uint8_t EXPECTED_CT[40] = {
    0x0b, 0x90, 0x0c, 0xbf, 0x4c, 0x7e, 0xe3, 0x53, 0xe8, 0xdf, 0x8b, 0x7a,
    0xe3, 0x7b, 0xc1, 0x74, 0x33, 0x57, 0xdb, 0xae, 0x5b, 0x58, 0x31, 0xd0,
    0xd3, 0x96, 0xb2, 0x5d, 0x1e, 0xfc, 0x54, 0x82, 0x7b, 0x49, 0xf3, 0xd9,
    0x7c, 0x6c, 0xd6, 0x8e,
};

int main()
{
  static uint8_t buf[40];
  int errors = 0;
  unsigned long enc_cycles, enc_instrs, dec_cycles, dec_instrs;

  printf("AES-128-CTR Benchmark - 40 bytes\n");

  memcpy(buf, PT, sizeof(buf));

  BENCH_ENABLE();
  BENCH_START();
  aes128_ctr_crypt(KEY, COUNTER, buf, sizeof(buf));
  BENCH_READ(enc_cycles, enc_instrs);

  for (int i = 0; i < 40; i++) {
    if (buf[i] != EXPECTED_CT[i]) {
      printf("!!! Ciphertext mismatch at byte %d: expected 0x%02x, got 0x%02x !!!\n", i, EXPECTED_CT[i], buf[i]);
      errors++;
    }
  }

  // CTR decrypt is the identical operation (re-apply the same keystream).
  BENCH_START();
  aes128_ctr_crypt(KEY, COUNTER, buf, sizeof(buf));
  BENCH_READ(dec_cycles, dec_instrs);

  for (int i = 0; i < 40; i++) {
    if (buf[i] != PT[i]) {
      printf("!!! Decrypted plaintext mismatch at byte %d: expected 0x%02x, got 0x%02x !!!\n", i, PT[i], buf[i]);
      errors++;
    }
  }

  // This platform's minimal sprintf() has no %f support, so throughput is
  // computed and printed as a fixed-point ratio (bits/cycle * 10000)
  // instead of a float, to avoid silently corrupting the arg list.
  unsigned long enc_bpc_e4 = (8UL * sizeof(PT) * 10000UL) / enc_cycles;
  unsigned long dec_bpc_e4 = (8UL * sizeof(PT) * 10000UL) / dec_cycles;
  printf("encrypt cycles=%lu instrs=%lu throughput=%lu.%04lu bits/cycle, "
         "decrypt cycles=%lu instrs=%lu throughput=%lu.%04lu bits/cycle\n",
         enc_cycles, enc_instrs, enc_bpc_e4 / 10000, enc_bpc_e4 % 10000,
         dec_cycles, dec_instrs, dec_bpc_e4 / 10000, dec_bpc_e4 % 10000);

  if (errors == 0) printf("AES-128-CTR Benchmark terminated with no errors.\n");
  else              printf("AES-128-CTR Benchmark terminated with %d errors\n", errors);

  return errors;
}
