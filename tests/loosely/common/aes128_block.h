// Loosely-coupled AXI accelerator-backed AES-128 single-block cipher
// interface -- same signature as tests/software/common/aes128_block.h and
// tests/tightly/common/aes128_block.h so application-level code (aes_cbc.c,
// aes_ctr.c, aes_gcm.c, aes_xts.c, aes_encrypt/aes_decrypt) is byte-identical
// across all three trees. Built on kecc_aes_k_axi.h's MMIO driver, which
// internally caches the core's last-loaded (key, direction) schedule so
// repeated same-key block calls (CBC/CTR/GCM/XTS's normal usage pattern)
// only pay for one hardware key-schedule pulse, not one per block -- see
// kecc_aes_k_axi.c's aes_block_op() for the rationale.

#ifndef __AES128_BLOCK_H__
#define __AES128_BLOCK_H__

#include <stdint.h>
#include <string.h>
#include "kecc_aes_k_axi.h"

typedef struct {
  uint8_t key[16];
} aes128_ctx_t;

static inline void aes128_key_expand(aes128_ctx_t *ctx, const uint8_t key[16])
{
  memcpy(ctx->key, key, 16);
}

static inline void aes128_encrypt_block(const aes128_ctx_t *ctx, uint8_t block[16])
{
  uint8_t key32[32] = {0};
  uint8_t out[16];
  memcpy(key32, ctx->key, 16);
  kecc_aes_k_axi_aes_encrypt_block(key32, /*keylen256=*/0, block, out);
  memcpy(block, out, 16);
}

static inline void aes128_decrypt_block(const aes128_ctx_t *ctx, uint8_t block[16])
{
  uint8_t key32[32] = {0};
  uint8_t out[16];
  memcpy(key32, ctx->key, 16);
  kecc_aes_k_axi_aes_decrypt_block(key32, /*keylen256=*/0, block, out);
  memcpy(block, out, 16);
}

#endif
