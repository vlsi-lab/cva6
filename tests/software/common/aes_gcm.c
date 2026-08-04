// AES-128-GCM, built on the shared aes128_block.h single-block interface
// and ghash.h. Identical source on both the software and tightly trees.
//
// Deliberately does NOT call aes_ctr.c's aes128_ctr_crypt(): GCM's counter
// increments only the low 32 bits with wraparound (SP 800-38D's inc_32),
// different from aes_ctr.c's full 128-bit increment, and reusing it would
// mean re-running key expansion for every AES call GCM needs (H, the tag
// mask, and the payload keystream) instead of once. So GCM keeps its own
// small internal CTR loop against a single expanded key schedule.

#include <string.h>
#include "aes_gcm.h"
#include "aes128_block.h"
#include "ghash.h"

static void incr32(uint8_t block[16])
{
  for (int i = 15; i >= 12; i--) {
    if (++block[i] != 0) break;
  }
}

static void gcm_ctr_crypt(const aes128_ctx_t *ctx, uint8_t counter[16],
                           uint8_t *buf, size_t len)
{
  uint8_t keystream[16];
  size_t off = 0;
  while (off < len) {
    memcpy(keystream, counter, 16);
    aes128_encrypt_block(ctx, keystream);
    size_t n = (len - off < 16) ? (len - off) : 16;
    for (size_t i = 0; i < n; i++) buf[off + i] ^= keystream[i];
    incr32(counter);
    off += n;
  }
}

// ghash_before_crypt: decrypt must GHASH the ciphertext (the input) before
// the CTR pass overwrites buf with plaintext; encrypt must GHASH the
// ciphertext (the CTR pass's output) after.
static void gcm_core(const uint8_t key[16], const uint8_t iv[12],
                      const uint8_t *aad, size_t aad_len,
                      uint8_t *buf, size_t len, uint8_t tag_out[16],
                      int ghash_before_crypt)
{
  aes128_ctx_t ctx;
  uint8_t H[16] = {0};
  uint8_t J0[16], E_J0[16], ghash_out[16], counter[16];

  aes128_key_expand(&ctx, key);
  aes128_encrypt_block(&ctx, H); // H = E(K, 0^128)

  memcpy(J0, iv, 12);
  J0[12] = 0; J0[13] = 0; J0[14] = 0; J0[15] = 1;

  memcpy(counter, J0, 16);
  incr32(counter); // counter = inc32(J0)

  if (ghash_before_crypt) {
    ghash(H, aad, aad_len, buf, len, ghash_out);
    gcm_ctr_crypt(&ctx, counter, buf, len);
  } else {
    gcm_ctr_crypt(&ctx, counter, buf, len);
    ghash(H, aad, aad_len, buf, len, ghash_out);
  }

  memcpy(E_J0, J0, 16);
  aes128_encrypt_block(&ctx, E_J0); // E(K, J0)
  for (int i = 0; i < 16; i++) tag_out[i] = ghash_out[i] ^ E_J0[i];
}

void aes128_gcm_encrypt(const uint8_t key[16], const uint8_t iv[12],
                         const uint8_t *aad, size_t aad_len,
                         uint8_t *buf, size_t len, uint8_t tag[16])
{
  gcm_core(key, iv, aad, aad_len, buf, len, tag, /*ghash_before_crypt=*/0);
}

int aes128_gcm_decrypt(const uint8_t key[16], const uint8_t iv[12],
                        const uint8_t *aad, size_t aad_len,
                        uint8_t *buf, size_t len, const uint8_t tag[16])
{
  uint8_t computed_tag[16];
  gcm_core(key, iv, aad, aad_len, buf, len, computed_tag, /*ghash_before_crypt=*/1);

  uint8_t diff = 0;
  for (int i = 0; i < 16; i++) diff |= (uint8_t)(computed_tag[i] ^ tag[i]);
  return diff ? -1 : 0;
}
