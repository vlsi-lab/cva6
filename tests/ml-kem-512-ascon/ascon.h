/*
 * Ascon wrapper for Kyber - Provides incremental XOF/Hash interface
 * 
 * This replaces FIPS-202 (Keccak) with Ascon for Kyber-512
 * Mapping:
 *   - SHA3-256 (hash_h) -> Ascon-Hash (32 bytes)
 *   - SHA3-512 (hash_g) -> Ascon-XOF (64 bytes)
 *   - SHAKE128 (XOF for sampling) -> Ascon-XOF
 *   - SHAKE256 (PRF) -> Ascon-XOF
 */

#ifndef ASCON_H_
#define ASCON_H_

#include <stdint.h>
#include <stddef.h>

/* Ascon rate is 8 bytes (64 bits) */
#define ASCON_HASH_RATE 8
#define ASCON_XOF_RATE  8

/* Ascon internal state: 320 bits = 5 x 64-bit words */
typedef struct {
  uint64_t x0, x1, x2, x3, x4;
} ascon_permutation_state_t;

/* 
 * Ascon state with position tracking for incremental absorb/squeeze
 * Similar to keccak_state in fips202.h
 */
typedef struct {
  ascon_permutation_state_t s;
  unsigned int pos;      /* Position in current block during absorb */
  int phase;             /* 0: absorbing, 1: finalized/squeezing */
} ascon_state;

/* Initialization vectors */
#define ASCON_XOF_IV   0x00001c0000000000ULL  /* XOF mode: variable output */
#define ASCON_HASH_IV  0x00001c0000000020ULL  /* Hash mode: 32-byte output */

/* 
 * Namespace macros for Kyber compatibility 
 */
#define ASCON_NAMESPACE(s) pqcrystals_kyber_ascon_ref_##s

/* Helper functions */
static inline uint64_t ROR64(uint64_t x, int n) {
  return (x >> n) | (x << (64 - n));
}

/* Byte access macros */
#define ASCON_GETBYTE(x, i) ((uint8_t)((uint64_t)(x) >> (56 - 8 * (i))))
#define ASCON_SETBYTE(b, i) ((uint64_t)(b) << (56 - 8 * (i)))
#define ASCON_PAD(i) ASCON_SETBYTE(0x80, i)

/* Load bytes into 64-bit word (big-endian) */
static inline uint64_t ascon_loadbytes(const uint8_t* bytes, int n) {
  uint64_t x = 0;
  for (int i = 0; i < n; ++i) 
    x |= ASCON_SETBYTE(bytes[i], i);
  return x;
}

/* Store bytes from 64-bit word (big-endian) */
static inline void ascon_storebytes(uint8_t* bytes, uint64_t x, int n) {
  for (int i = 0; i < n; ++i) 
    bytes[i] = ASCON_GETBYTE(x, i);
}

/* Clear bytes in 64-bit word */
static inline uint64_t ascon_clearbytes(uint64_t x, int n) {
  for (int i = 0; i < n; ++i) 
    x &= ~ASCON_SETBYTE(0xff, i);
  return x;
}

/*
 * Ascon permutation rounds
 */
static inline void ascon_round(ascon_permutation_state_t* s, uint8_t C) {
  ascon_permutation_state_t t;
  
  /* Addition of round constant */
  s->x2 ^= C;
  
  /* Substitution layer */
  s->x0 ^= s->x4;
  s->x4 ^= s->x3;
  s->x2 ^= s->x1;
  
  /* Start of s-box */
  t.x0 = s->x0 ^ (~s->x1 & s->x2);
  t.x1 = s->x1 ^ (~s->x2 & s->x3);
  t.x2 = s->x2 ^ (~s->x3 & s->x4);
  t.x3 = s->x3 ^ (~s->x4 & s->x0);
  t.x4 = s->x4 ^ (~s->x0 & s->x1);
  
  /* End of s-box */
  t.x1 ^= t.x0;
  t.x0 ^= t.x4;
  t.x3 ^= t.x2;
  t.x2 = ~t.x2;
  
  /* Linear diffusion layer */
  s->x0 = t.x0 ^ ROR64(t.x0, 19) ^ ROR64(t.x0, 28);
  s->x1 = t.x1 ^ ROR64(t.x1, 61) ^ ROR64(t.x1, 39);
  s->x2 = t.x2 ^ ROR64(t.x2, 1)  ^ ROR64(t.x2, 6);
  s->x3 = t.x3 ^ ROR64(t.x3, 10) ^ ROR64(t.x3, 17);
  s->x4 = t.x4 ^ ROR64(t.x4, 7)  ^ ROR64(t.x4, 41);
}

/* 12-round permutation (used for init, absorb, squeeze) */
static inline void ascon_p12(ascon_permutation_state_t* s) {
  ascon_round(s, 0xf0);
  ascon_round(s, 0xe1);
  ascon_round(s, 0xd2);
  ascon_round(s, 0xc3);
  ascon_round(s, 0xb4);
  ascon_round(s, 0xa5);
  ascon_round(s, 0x96);
  ascon_round(s, 0x87);
  ascon_round(s, 0x78);
  ascon_round(s, 0x69);
  ascon_round(s, 0x5a);
  ascon_round(s, 0x4b);
}

/* 
 * ============================================================
 * XOF Interface (similar to SHAKE)
 * ============================================================
 */

/* Initialize Ascon-XOF state */
#define ascon_xof_init ASCON_NAMESPACE(ascon_xof_init)
void ascon_xof_init(ascon_state *state);

/* Absorb data into Ascon-XOF state */
#define ascon_xof_absorb ASCON_NAMESPACE(ascon_xof_absorb)
void ascon_xof_absorb(ascon_state *state, const uint8_t *in, size_t inlen);

/* Finalize absorbing phase */
#define ascon_xof_finalize ASCON_NAMESPACE(ascon_xof_finalize)
void ascon_xof_finalize(ascon_state *state);

/* Squeeze output from Ascon-XOF state */
#define ascon_xof_squeeze ASCON_NAMESPACE(ascon_xof_squeeze)
void ascon_xof_squeeze(uint8_t *out, size_t outlen, ascon_state *state);

/* Absorb once and finalize (convenience) */
#define ascon_xof_absorb_once ASCON_NAMESPACE(ascon_xof_absorb_once)
void ascon_xof_absorb_once(ascon_state *state, const uint8_t *in, size_t inlen);

/* Squeeze full blocks */
#define ascon_xof_squeezeblocks ASCON_NAMESPACE(ascon_xof_squeezeblocks)
void ascon_xof_squeezeblocks(uint8_t *out, size_t nblocks, ascon_state *state);

/* One-shot XOF: absorb input and squeeze output */
#define ascon_xof ASCON_NAMESPACE(ascon_xof)
void ascon_xof(uint8_t *out, size_t outlen, const uint8_t *in, size_t inlen);

/* 
 * ============================================================
 * Hash Interface (replaces SHA3-256/SHA3-512)
 * ============================================================
 */

/* Ascon-Hash: 32-byte output (replaces SHA3-256) */
#define ascon_hash_256 ASCON_NAMESPACE(ascon_hash_256)
void ascon_hash_256(uint8_t h[32], const uint8_t *in, size_t inlen);

/* Ascon-XOF with 64-byte output (replaces SHA3-512) */
#define ascon_hash_512 ASCON_NAMESPACE(ascon_hash_512)
void ascon_hash_512(uint8_t h[64], const uint8_t *in, size_t inlen);

#endif /* ASCON_H_ */
