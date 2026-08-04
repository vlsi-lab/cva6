// AES-128-CTR, built on the shared aes128_block.h single-block interface.
// Identical source on both the software and tightly trees.

#include <string.h>
#include "aes_ctr.h"
#include "aes128_block.h"

void aes128_ctr_crypt(const uint8_t key[16], const uint8_t counter_block[16],
                       uint8_t *buf, size_t nbytes)
{
  aes128_ctx_t ctx;
  uint8_t counter[16], keystream[16];
  aes128_key_expand(&ctx, key);
  memcpy(counter, counter_block, 16);

  size_t off = 0;
  while (off < nbytes) {
    memcpy(keystream, counter, 16);
    aes128_encrypt_block(&ctx, keystream);

    size_t n = (nbytes - off < 16) ? (nbytes - off) : 16;
    for (size_t i = 0; i < n; i++) buf[off + i] ^= keystream[i];
    off += n;

    for (int i = 15; i >= 0; i--) {
      if (++counter[i] != 0) break;
    }
  }
}
