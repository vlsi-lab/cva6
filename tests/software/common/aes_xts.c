// AES-128-XTS, built on the shared aes128_block.h single-block interface.
// Identical source on both the software and tightly trees.

#include <string.h>
#include "aes_xts.h"
#include "aes128_block.h"

// Doubling (multiply by the field element x) in XTS's little-endian
// GF(2^128) convention (reduction polynomial x^128+x^7+x^2+x+1, feedback
// byte 0x87) -- distinct from ghash.c's MSB-first convention.
static void xts_double(uint8_t T[16])
{
  uint8_t carry = 0;
  for (int i = 0; i < 16; i++) {
    uint8_t new_carry = (uint8_t)((T[i] >> 7) & 1);
    T[i] = (uint8_t)((T[i] << 1) | carry);
    carry = new_carry;
  }
  if (carry) T[0] ^= 0x87;
}

static void xts_init_tweak(const aes128_ctx_t *ctx2, uint64_t sector, uint8_t T[16])
{
  memset(T, 0, 16);
  for (int i = 0; i < 8; i++) T[i] = (uint8_t)(sector >> (8 * i)); // little-endian sector number
  aes128_encrypt_block(ctx2, T); // T0 = E(Key2, sector_LE128)
}

void aes128_xts_encrypt(const uint8_t key1[16], const uint8_t key2[16],
                         uint64_t sector, uint8_t *buf, size_t nblocks)
{
  aes128_ctx_t ctx1, ctx2;
  uint8_t T[16];
  aes128_key_expand(&ctx1, key1);
  aes128_key_expand(&ctx2, key2);
  xts_init_tweak(&ctx2, sector, T);

  for (size_t b = 0; b < nblocks; b++) {
    uint8_t *block = buf + 16 * b;
    for (int i = 0; i < 16; i++) block[i] ^= T[i];
    aes128_encrypt_block(&ctx1, block);
    for (int i = 0; i < 16; i++) block[i] ^= T[i];
    xts_double(T);
  }
}

void aes128_xts_decrypt(const uint8_t key1[16], const uint8_t key2[16],
                         uint64_t sector, uint8_t *buf, size_t nblocks)
{
  aes128_ctx_t ctx1, ctx2;
  uint8_t T[16];
  aes128_key_expand(&ctx1, key1);
  aes128_key_expand(&ctx2, key2);
  xts_init_tweak(&ctx2, sector, T);

  for (size_t b = 0; b < nblocks; b++) {
    uint8_t *block = buf + 16 * b;
    for (int i = 0; i < 16; i++) block[i] ^= T[i];
    aes128_decrypt_block(&ctx1, block);
    for (int i = 0; i < 16; i++) block[i] ^= T[i];
    xts_double(T);
  }
}
