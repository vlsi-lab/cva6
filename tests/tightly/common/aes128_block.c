// Coprocessor-backed AES-128 single-block cipher, built on aes64_copro.h.
// Key-schedule/round sequence is the same one already validated against the
// FIPS-197 vector in tests/aes64_xif_tests/aes128_full.c.

#include "aes128_block.h"
#include "aes64_copro.h"

#define NR 10

static uint64_t load64le(const uint8_t x[8])
{
  uint64_t r = 0;
  for (int i = 0; i < 8; i++) r |= (uint64_t)x[i] << (8 * i);
  return r;
}

static void store64le(uint8_t x[8], uint64_t u)
{
  for (int i = 0; i < 8; i++) x[i] = (uint8_t)(u >> (8 * i));
}

void aes128_key_expand(aes128_ctx_t *ctx, const uint8_t key[16])
{
  uint64_t a2 = load64le(key), a3 = load64le(key + 8), t0;
  ctx->enc_rk[0] = a2;
  ctx->enc_rk[1] = a3;

#define KS_ROUND(rnum) \
  AES64KS1I(t0, a3, rnum); \
  a2 = aes64ks2(t0, a2); \
  a3 = aes64ks2(a2, a3); \
  ctx->enc_rk[2 * (rnum) + 2] = a2; \
  ctx->enc_rk[2 * (rnum) + 3] = a3;

  KS_ROUND(0)
  KS_ROUND(1)
  KS_ROUND(2)
  KS_ROUND(3)
  KS_ROUND(4)
  KS_ROUND(5)
  KS_ROUND(6)
  KS_ROUND(7)
  KS_ROUND(8)
  KS_ROUND(9)
#undef KS_ROUND

  ctx->dec_rk[0] = ctx->enc_rk[0];
  ctx->dec_rk[1] = ctx->enc_rk[1];
  for (int i = 1; i < NR; i++) {
    ctx->dec_rk[2 * i]     = aes64im(ctx->enc_rk[2 * i]);
    ctx->dec_rk[2 * i + 1] = aes64im(ctx->enc_rk[2 * i + 1]);
  }
  ctx->dec_rk[2 * NR]     = ctx->enc_rk[2 * NR];
  ctx->dec_rk[2 * NR + 1] = ctx->enc_rk[2 * NR + 1];
}

void aes128_encrypt_block(const aes128_ctx_t *ctx, uint8_t block[16])
{
  uint64_t hi = load64le(block) ^ ctx->enc_rk[0];
  uint64_t lo = load64le(block + 8) ^ ctx->enc_rk[1];

  for (int i = 1; i < NR; i++) {
    uint64_t new_hi = aes64esm(hi, lo);
    uint64_t new_lo = aes64esm(lo, hi);
    hi = new_hi ^ ctx->enc_rk[2 * i];
    lo = new_lo ^ ctx->enc_rk[2 * i + 1];
  }
  uint64_t new_hi = aes64es(hi, lo);
  uint64_t new_lo = aes64es(lo, hi);
  hi = new_hi ^ ctx->enc_rk[2 * NR];
  lo = new_lo ^ ctx->enc_rk[2 * NR + 1];

  store64le(block, hi);
  store64le(block + 8, lo);
}

void aes128_decrypt_block(const aes128_ctx_t *ctx, uint8_t block[16])
{
  uint64_t hi = load64le(block) ^ ctx->dec_rk[2 * NR];
  uint64_t lo = load64le(block + 8) ^ ctx->dec_rk[2 * NR + 1];

  for (int i = NR - 1; i >= 1; i--) {
    uint64_t new_hi = aes64dsm(hi, lo);
    uint64_t new_lo = aes64dsm(lo, hi);
    hi = new_hi ^ ctx->dec_rk[2 * i];
    lo = new_lo ^ ctx->dec_rk[2 * i + 1];
  }
  uint64_t new_hi = aes64ds(hi, lo);
  uint64_t new_lo = aes64ds(lo, hi);
  hi = new_hi ^ ctx->dec_rk[0];
  lo = new_lo ^ ctx->dec_rk[1];

  store64le(block, hi);
  store64le(block + 8, lo);
}
