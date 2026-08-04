// GHASH (AES-GCM's GF(2^128) universal hash), NIST SP 800-38D. Identical
// source on both the software and tightly trees -- pure field math, no AES
// calls, so nothing here differs between the two.

#include <string.h>
#include "ghash.h"

void gf128_mul(uint8_t out[16], const uint8_t a[16], const uint8_t b[16])
{
  uint8_t Z[16] = {0};
  uint8_t V[16];
  memcpy(V, b, 16);

  for (int i = 0; i < 128; i++) {
    int bit = (a[i / 8] >> (7 - (i % 8))) & 1;
    if (bit) {
      for (int j = 0; j < 16; j++) Z[j] ^= V[j];
    }
    int lsb = V[15] & 1;
    for (int j = 15; j > 0; j--) {
      V[j] = (uint8_t)((V[j] >> 1) | ((V[j - 1] & 1) << 7));
    }
    V[0] = (uint8_t)(V[0] >> 1);
    if (lsb) V[0] ^= 0xE1;
  }

  memcpy(out, Z, 16);
}

static void ghash_block(uint8_t Y[16], const uint8_t H[16],
                         const uint8_t *data, size_t off, size_t len)
{
  uint8_t block[16] = {0};
  size_t n = (len - off < 16) ? (len - off) : 16;
  memcpy(block, data + off, n);
  for (int j = 0; j < 16; j++) Y[j] ^= block[j];
  gf128_mul(Y, Y, H);
}

void ghash(const uint8_t H[16], const uint8_t *aad, size_t aad_len,
           const uint8_t *data, size_t data_len, uint8_t out[16])
{
  uint8_t Y[16] = {0};
  size_t off;

  for (off = 0; off < aad_len; off += 16) ghash_block(Y, H, aad, off, aad_len);
  for (off = 0; off < data_len; off += 16) ghash_block(Y, H, data, off, data_len);

  uint8_t lenblock[16];
  uint64_t aad_bits = (uint64_t)aad_len * 8;
  uint64_t data_bits = (uint64_t)data_len * 8;
  for (int j = 0; j < 8; j++) lenblock[j]     = (uint8_t)(aad_bits  >> (56 - 8 * j));
  for (int j = 0; j < 8; j++) lenblock[8 + j] = (uint8_t)(data_bits >> (56 - 8 * j));
  for (int j = 0; j < 16; j++) Y[j] ^= lenblock[j];
  gf128_mul(Y, Y, H);

  memcpy(out, Y, 16);
}
