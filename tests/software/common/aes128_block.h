// Software AES-128 single-block cipher interface, shared with the tightly
// (coprocessor-backed) tree so application-level code (aes_cbc.c, etc.) can
// be identical on both sides. See tests/tightly/common/aes128_block.h for
// the coprocessor-backed implementation of this same interface.

#ifndef __AES128_BLOCK_H__
#define __AES128_BLOCK_H__

#include <stdint.h>
#include "aes.h"

typedef struct AES_ctx aes128_ctx_t;

static inline void aes128_key_expand(aes128_ctx_t *ctx, const uint8_t key[16])
{
  AES_init_ctx(ctx, key);
}

static inline void aes128_encrypt_block(const aes128_ctx_t *ctx, uint8_t block[16])
{
  AES_ECB_encrypt(ctx, block);
}

static inline void aes128_decrypt_block(const aes128_ctx_t *ctx, uint8_t block[16])
{
  AES_ECB_decrypt(ctx, block);
}

#endif
