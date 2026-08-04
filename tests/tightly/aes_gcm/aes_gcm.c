// AES-128-GCM benchmark: 20 bytes AAD + 48 bytes (3-block) payload,
// encrypt-then-decrypt round-trip, plus a tampered-tag rejection check.
// Checked against ciphertext/tag independently computed via Python
// pycryptodome (Crypto.Cipher.AES, MODE_GCM). Identical source on the
// software and tightly trees -- only the linked aes128_block.c
// implementation differs, per run.sh. 96-bit IV only (see aes_gcm.h).
//
// The most convincing authenticated-encryption / secure-channel workload
// in this suite: unlike aes_ctr, the cycle count here also reflects
// GHASH's GF(2^128) authentication pass, not just the AES keystream.

#include <string.h>
#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "aes_gcm.h"

static const uint8_t KEY[16] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
    0x0c, 0x0d, 0x0e, 0x0f,
};

static const uint8_t IV[12] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
};

static const uint8_t AAD[20] = {
    0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab,
    0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3,
};

static const uint8_t PT[48] = {
    0x01, 0x04, 0x07, 0x0a, 0x0d, 0x10, 0x13, 0x16, 0x19, 0x1c, 0x1f, 0x22,
    0x25, 0x28, 0x2b, 0x2e, 0x31, 0x34, 0x37, 0x3a, 0x3d, 0x40, 0x43, 0x46,
    0x49, 0x4c, 0x4f, 0x52, 0x55, 0x58, 0x5b, 0x5e, 0x61, 0x64, 0x67, 0x6a,
    0x6d, 0x70, 0x73, 0x76, 0x79, 0x7c, 0x7f, 0x82, 0x85, 0x88, 0x8b, 0x8e,
};

static const uint8_t EXPECTED_CT[48] = {
    0x92, 0x68, 0xa0, 0xc4, 0x6b, 0x0b, 0xe4, 0x42, 0x52, 0xce, 0x7e, 0xa8,
    0x13, 0x8b, 0x5b, 0x26, 0x82, 0x12, 0x2d, 0xdc, 0x6e, 0xad, 0xbe, 0xb0,
    0xaf, 0x6d, 0xbe, 0x7f, 0x41, 0x1c, 0xf9, 0x32, 0xe4, 0xc0, 0xbc, 0x9d,
    0x99, 0xf0, 0xc4, 0x95, 0x39, 0x88, 0x76, 0x65, 0x45, 0x01, 0x5c, 0x1c,
};

static const uint8_t EXPECTED_TAG[16] = {
    0x42, 0xdf, 0x7c, 0x2a, 0xdb, 0xb9, 0x5c, 0xbd, 0x2f, 0xb0, 0xf0, 0x3a,
    0x26, 0x19, 0x90, 0x68,
};

int main()
{
  static uint8_t buf[48];
  uint8_t tag[16];
  int errors = 0;
  unsigned long enc_cycles, enc_instrs, dec_cycles, dec_instrs;

  printf("AES-128-GCM Benchmark - 20 B AAD + 48 B payload\n");

  memcpy(buf, PT, sizeof(buf));

  BENCH_ENABLE();
  BENCH_START();
  aes128_gcm_encrypt(KEY, IV, AAD, sizeof(AAD), buf, sizeof(buf), tag);
  BENCH_READ(enc_cycles, enc_instrs);

  for (int i = 0; i < 48; i++) {
    if (buf[i] != EXPECTED_CT[i]) {
      printf("!!! Ciphertext mismatch at byte %d: expected 0x%02x, got 0x%02x !!!\n", i, EXPECTED_CT[i], buf[i]);
      errors++;
    }
  }
  for (int i = 0; i < 16; i++) {
    if (tag[i] != EXPECTED_TAG[i]) {
      printf("!!! Tag mismatch at byte %d: expected 0x%02x, got 0x%02x !!!\n", i, EXPECTED_TAG[i], tag[i]);
      errors++;
    }
  }

  BENCH_START();
  int rc = aes128_gcm_decrypt(KEY, IV, AAD, sizeof(AAD), buf, sizeof(buf), EXPECTED_TAG);
  BENCH_READ(dec_cycles, dec_instrs);

  if (rc != 0) {
    printf("!!! GCM decrypt: tag verification failed (rc=%d) !!!\n", rc);
    errors++;
  }
  for (int i = 0; i < 48; i++) {
    if (buf[i] != PT[i]) {
      printf("!!! Decrypted plaintext mismatch at byte %d: expected 0x%02x, got 0x%02x !!!\n", i, PT[i], buf[i]);
      errors++;
    }
  }

  // Tampered-tag rejection: a flipped tag byte must be rejected, not
  // silently accepted -- the whole point of the "authenticated" in AEAD.
  uint8_t bad_tag[16];
  memcpy(bad_tag, EXPECTED_TAG, 16);
  bad_tag[0] ^= 0xFF;
  memcpy(buf, EXPECTED_CT, sizeof(buf));
  if (aes128_gcm_decrypt(KEY, IV, AAD, sizeof(AAD), buf, sizeof(buf), bad_tag) == 0) {
    printf("!!! GCM decrypt accepted a tampered tag !!!\n");
    errors++;
  }

  // Throughput counts payload bits only (not AAD) -- AAD's authentication
  // cost is reflected in the cycle count itself, not the throughput figure.
  // This platform's minimal sprintf() has no %f support, so throughput is
  // computed and printed as a fixed-point ratio (bits/cycle * 10000)
  // instead of a float, to avoid silently corrupting the arg list.
  unsigned long enc_bpc_e4 = (8UL * sizeof(PT) * 10000UL) / enc_cycles;
  unsigned long dec_bpc_e4 = (8UL * sizeof(PT) * 10000UL) / dec_cycles;
  printf("encrypt cycles=%lu instrs=%lu throughput=%lu.%04lu bits/cycle, "
         "decrypt cycles=%lu instrs=%lu throughput=%lu.%04lu bits/cycle\n",
         enc_cycles, enc_instrs, enc_bpc_e4 / 10000, enc_bpc_e4 % 10000,
         dec_cycles, dec_instrs, dec_bpc_e4 / 10000, dec_bpc_e4 % 10000);

  if (errors == 0) printf("AES-128-GCM Benchmark terminated with no errors.\n");
  else              printf("AES-128-GCM Benchmark terminated with %d errors\n", errors);

  return errors;
}
