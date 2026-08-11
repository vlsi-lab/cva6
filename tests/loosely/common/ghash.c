// GHASH (AES-GCM's GF(2^128) authentication multiply), NIST SP 800-38D --
// clmul/clmulh-accelerated variant (RISC-V B-extension, see
// clmul_native.h). AES in this tree still goes through the kecc_aes_k_xif
// coprocessor (aes64es/esm/ds/dsm/ks2/im/ks1i, see aes64_copro.h /
// aes128_block.c) -- only GHASH uses the native carry-less multiplier
// instead of a coprocessor primitive. (A dedicated GHASH_CLMULL/GHASH_CLMULH
// coprocessor instruction pair was prototyped and measured here first --
// see tests/result.md's "Results -- GHASH block-multiply" -- and removed:
// identical instruction count to native clmul/clmulh, no cycle advantage.)
//
// Same ghash()/gf128_mul() interface and byte/bit semantics as
// tests/software/common/ghash.c (bit-serial reference) and
// tests/native_clmul/common/ghash.c (identical algorithm, this file is a
// straight copy of it). gf128_mul here is computed via bit-reflection + a
// schoolbook 64x64->128 carry-less multiply (4 partial products from
// clmul/clmulh) + shift-xor reduction, the standard technique for computing
// GHASH with a native carry-less multiplier (see e.g. Gueron & Kounavis,
// "Carry-Less Multiplication and Its Usage for Computing the GCM Mode",
// Intel whitepaper 2010).
//
// GCM's bit convention (SP 800-38D): a 16-byte block b[0..15] represents
// the field element sum_i X_i * alpha^i, where X_i is bit (7-(i%8)) of
// byte b[i/8] (i.e. bit i, MSB-first per byte, *increasing* degree as you
// read left to right) -- see tests/software/common/ghash.c's bit-serial
// gf128_mul for the literal algorithm this must match.
//
// clmul/clmulh instead operate on the "natural" convention: bit k of a
// 64-bit register is the coefficient of x^k (LSB = x^0). To bridge the
// two, reverse the BIT order within each byte (keep byte order the same --
// byte 0 stays the least-significant byte of the resulting integer, since
// it holds the lowest-degree terms X_0..X_7). This transform is validated
// (not just derived) against the trusted bit-serial reference across 1000+
// random 16-byte pairs in a standalone Python/host-C harness -- see
// tests/native_clmul/common/ghash.c for the validation notes.
//
// After reflecting both operands into this "natural" 128-bit integer form,
// the multiply is standard schoolbook GF(2)-polynomial multiplication
// (using the SAME reduction polynomial, x^128+x^7+x^2+x+1, because this
// bit-reflection is exactly the classical trick that keeps GCM's chosen
// polynomial reduction-compatible in both bit orders), followed by
// reducing the 256-bit raw product mod x^128+x^7+x^2+x+1, then reflecting
// the 128-bit result back into GCM's byte/bit order.

#include <string.h>
#include "ghash.h"
#include "clmul_native.h"

static uint8_t bitreverse_byte(uint8_t b)
{
  b = (uint8_t)(((b & 0xF0) >> 4) | ((b & 0x0F) << 4));
  b = (uint8_t)(((b & 0xCC) >> 2) | ((b & 0x33) << 2));
  b = (uint8_t)(((b & 0xAA) >> 1) | ((b & 0x55) << 1));
  return b;
}

// Reverses the bit order WITHIN each byte; byte order (array index) is
// unchanged. Converts between GCM's MSB-first-per-byte convention and the
// "bit k = coefficient of x^k" convention clmul expects, and vice versa
// (the transform is its own inverse).
static void reflect_bytes(uint8_t out[16], const uint8_t in[16])
{
  for (int i = 0; i < 16; i++) out[i] = bitreverse_byte(in[i]);
}

static uint64_t load_le64(const uint8_t p[8])
{
  uint64_t v = 0;
  for (int i = 0; i < 8; i++) v |= ((uint64_t)p[i]) << (8 * i);
  return v;
}

static void store_le64(uint8_t p[8], uint64_t v)
{
  for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * i));
}

void gf128_mul(uint8_t out[16], const uint8_t a[16], const uint8_t b[16])
{
  uint8_t ra[16], rb[16];
  reflect_bytes(ra, a);
  reflect_bytes(rb, b);

  // Little-endian pack: byte 0 of the reflected block is the
  // least-significant byte of the 128-bit integer (a_lo/b_lo hold the
  // low-degree half, a_hi/b_hi the high-degree half).
  uint64_t a_lo = load_le64(&ra[0]);
  uint64_t a_hi = load_le64(&ra[8]);
  uint64_t b_lo = load_le64(&rb[0]);
  uint64_t b_hi = load_le64(&rb[8]);

  // Schoolbook 128x128 -> 256-bit carry-less multiply as 4 partial
  // 64x64 -> 128-bit products (clmul = low 64 bits, clmulh = high 64 bits
  // of each partial product), combined with the correct 64-bit shifts.
  uint64_t t0_lo = clmul(a_lo, b_lo), t0_hi = clmulh(a_lo, b_lo);
  uint64_t t1_lo = clmul(a_lo, b_hi), t1_hi = clmulh(a_lo, b_hi);
  uint64_t t2_lo = clmul(a_hi, b_lo), t2_hi = clmulh(a_hi, b_lo);
  uint64_t t3_lo = clmul(a_hi, b_hi), t3_hi = clmulh(a_hi, b_hi);

  uint64_t mid_lo = t1_lo ^ t2_lo;
  uint64_t mid_hi = t1_hi ^ t2_hi;

  // 256-bit raw product, 4 little-endian 64-bit limbs (X0 = lowest degree).
  uint64_t X0 = t0_lo;
  uint64_t X1 = t0_hi ^ mid_lo;
  uint64_t X2 = mid_hi ^ t3_lo;
  uint64_t X3 = t3_hi;

  // Shift-xor reduction mod M(x) = x^128 + x^7 + x^2 + x + 1.
  // x^128 === C(x) = x^7+x^2+x+1 (mod M), i.e. the 8-bit constant 0x87
  // (bits 7,2,1,0 set) in the "bit k = coeff of x^k" convention.
  //
  // The high 128 bits of the raw product (X2:X3, representing the
  // x^128..x^255 part) contribute (X2:X3) * x^128 === (X2:X3) * C(x).
  // Since C(x) has degree 7, (X2:X3)*C(x) has degree <= 127+7 = 134: still
  // overflows x^128 by up to 7 bits, so fold that (<=7-bit) overflow back
  // in the same way once more -- its product with C(x) has degree <= 13,
  // which fits entirely below x^128 and needs no further folding.
  const uint64_t C = 0x87;

  uint64_t hl_lo = clmul(X2, C), hl_hi = clmulh(X2, C);
  uint64_t hh_lo = clmul(X3, C), hh_hi = clmulh(X3, C);

  uint64_t lo2_w0 = hl_lo;
  uint64_t lo2_w1 = hl_hi ^ hh_lo;
  uint64_t hi2_w0 = hh_hi; // always < 2^7 (degree <= 6 within this word)

  uint64_t hi2_lo = clmul(hi2_w0, C); // clmulh(hi2_w0, C) is always 0 here

  uint64_t R0 = X0 ^ lo2_w0 ^ hi2_lo;
  uint64_t R1 = X1 ^ lo2_w1;

  uint8_t result[16];
  store_le64(&result[0], R0);
  store_le64(&result[8], R1);

  reflect_bytes(out, result);
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
