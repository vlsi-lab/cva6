// AES-128-XTS benchmark, one 48-byte (3-block) sector. Checked against
// ciphertext independently computed via Python's `cryptography` library
// (cryptography.hazmat.primitives.ciphers.modes.XTS, key = KEY1||KEY2).
// Identical source on the software and tightly trees -- only the linked
// aes128_block.c implementation differs, per run.sh. Whole-block sectors
// only (no ciphertext stealing), see aes_xts.h.
//
// XTS is standardized specifically for storage-device confidentiality; it
// does not authenticate the data or its origin (compare against aes_gcm).

#include <string.h>
#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "aes_xts.h"

static const uint8_t KEY1[16] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
    0x0c, 0x0d, 0x0e, 0x0f,
};

static const uint8_t KEY2[16] = {
    0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b,
    0x4c, 0x4d, 0x4e, 0x4f,
};

#define SECTOR 1ULL

static const uint8_t PT[48] = {
    0x01, 0x04, 0x07, 0x0a, 0x0d, 0x10, 0x13, 0x16, 0x19, 0x1c, 0x1f, 0x22,
    0x25, 0x28, 0x2b, 0x2e, 0x31, 0x34, 0x37, 0x3a, 0x3d, 0x40, 0x43, 0x46,
    0x49, 0x4c, 0x4f, 0x52, 0x55, 0x58, 0x5b, 0x5e, 0x61, 0x64, 0x67, 0x6a,
    0x6d, 0x70, 0x73, 0x76, 0x79, 0x7c, 0x7f, 0x82, 0x85, 0x88, 0x8b, 0x8e,
};

static const uint8_t EXPECTED_CT[48] = {
    0x31, 0x99, 0x2c, 0x35, 0x5d, 0x92, 0x88, 0x86, 0xf2, 0x40, 0x80, 0xb7,
    0x30, 0x6e, 0x24, 0x6e, 0xa7, 0xd9, 0x96, 0x4e, 0xdf, 0x7c, 0x11, 0x82,
    0x8e, 0xf9, 0xb6, 0x3a, 0xbc, 0xbe, 0xbb, 0x28, 0x2d, 0xff, 0x04, 0x6c,
    0x85, 0x35, 0x59, 0x1a, 0x26, 0x3a, 0xfa, 0x0f, 0xeb, 0x36, 0x1f, 0xbd,
};

int main()
{
  static uint8_t buf[48];
  int errors = 0;
  unsigned long enc_cycles, enc_instrs, dec_cycles, dec_instrs;

  printf("AES-128-XTS Benchmark - 1 sector, 3 blocks\n");

  memcpy(buf, PT, sizeof(buf));

  BENCH_ENABLE();
  BENCH_START();
  aes128_xts_encrypt(KEY1, KEY2, SECTOR, buf, 3);
  BENCH_READ(enc_cycles, enc_instrs);

  for (int i = 0; i < 48; i++) {
    if (buf[i] != EXPECTED_CT[i]) {
      printf("!!! Ciphertext mismatch at byte %d: expected 0x%02x, got 0x%02x !!!\n", i, EXPECTED_CT[i], buf[i]);
      errors++;
    }
  }

  BENCH_START();
  aes128_xts_decrypt(KEY1, KEY2, SECTOR, buf, 3);
  BENCH_READ(dec_cycles, dec_instrs);

  for (int i = 0; i < 48; i++) {
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

  if (errors == 0) printf("AES-128-XTS Benchmark terminated with no errors.\n");
  else              printf("AES-128-XTS Benchmark terminated with %d errors\n", errors);

  return errors;
}
