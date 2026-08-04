// Coprocessor-backed AES-128 single-block cipher interface -- same signature
// as tests/software/common/aes128_block.h so application-level code
// (aes_cbc.c, etc.) is identical on both trees. Built on aes64_copro.h
// (aes64es/esm/ds/dsm/ks2/im/ks1i), reusing the key-schedule/round sequence
// already validated against FIPS-197 in tests/aes64_xif_tests/aes128_full.c.

#ifndef __AES128_BLOCK_H__
#define __AES128_BLOCK_H__

#include <stdint.h>

typedef struct {
  uint64_t enc_rk[22];  // 11 round keys (encrypt schedule), hi/lo halves
  uint64_t dec_rk[22];  // same round keys, aes64im-transformed for rounds 1..9
} aes128_ctx_t;

void aes128_key_expand(aes128_ctx_t *ctx, const uint8_t key[16]);
void aes128_encrypt_block(const aes128_ctx_t *ctx, uint8_t block[16]);
void aes128_decrypt_block(const aes128_ctx_t *ctx, uint8_t block[16]);

#endif
