// AES-128-CBC, built on the shared aes128_block.h single-block interface.
// Identical source on both the software and tightly trees.

#include <string.h>
#include "aes_cbc.h"
#include "aes128_block.h"

void aes128_cbc_encrypt(const uint8_t key[16], const uint8_t iv[16],
                         uint8_t *buf, size_t nblocks)
{
  aes128_ctx_t ctx;
  uint8_t chain[16];
  aes128_key_expand(&ctx, key);
  memcpy(chain, iv, 16);

  for (size_t b = 0; b < nblocks; b++) {
    uint8_t *block = buf + 16 * b;
    for (int i = 0; i < 16; i++) block[i] ^= chain[i];
    aes128_encrypt_block(&ctx, block);
    memcpy(chain, block, 16);
  }
}

void aes128_cbc_decrypt(const uint8_t key[16], const uint8_t iv[16],
                         uint8_t *buf, size_t nblocks)
{
  aes128_ctx_t ctx;
  uint8_t chain[16];
  uint8_t next_chain[16];
  aes128_key_expand(&ctx, key);
  memcpy(chain, iv, 16);

  for (size_t b = 0; b < nblocks; b++) {
    uint8_t *block = buf + 16 * b;
    memcpy(next_chain, block, 16);
    aes128_decrypt_block(&ctx, block);
    for (int i = 0; i < 16; i++) block[i] ^= chain[i];
    memcpy(chain, next_chain, 16);
  }
}
