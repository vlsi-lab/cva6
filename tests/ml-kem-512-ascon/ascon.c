/*
 * Ascon XOF/Hash implementation for Kyber
 * Provides an incremental absorb/squeeze interface similar to Keccak/SHAKE
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "ascon.h"

/*
 * Initialize Ascon-XOF state
 */
void ascon_xof_init(ascon_state *state) {
  state->s.x0 = ASCON_XOF_IV;
  state->s.x1 = 0;
  state->s.x2 = 0;
  state->s.x3 = 0;
  state->s.x4 = 0;
  state->pos = 0;
  state->phase = 0;
  ascon_p12(&state->s);
}

/*
 * Absorb data into Ascon-XOF state (incremental)
 */
void ascon_xof_absorb(ascon_state *state, const uint8_t *in, size_t inlen) {
  size_t i;
  
  /* If we have buffered data, fill the current block first */
  if (state->pos > 0) {
    while (state->pos < ASCON_XOF_RATE && inlen > 0) {
      /* XOR byte into x0 at position state->pos */
      state->s.x0 ^= ASCON_SETBYTE(*in, state->pos);
      state->pos++;
      in++;
      inlen--;
    }
    
    if (state->pos == ASCON_XOF_RATE) {
      ascon_p12(&state->s);
      state->pos = 0;
    }
  }
  
  /* Absorb full blocks */
  while (inlen >= ASCON_XOF_RATE) {
    state->s.x0 ^= ascon_loadbytes(in, ASCON_XOF_RATE);
    ascon_p12(&state->s);
    in += ASCON_XOF_RATE;
    inlen -= ASCON_XOF_RATE;
  }
  
  /* Buffer remaining bytes */
  for (i = 0; i < inlen; i++) {
    state->s.x0 ^= ASCON_SETBYTE(in[i], i);
  }
  state->pos = (unsigned int)inlen;
}

/*
 * Finalize the absorbing phase (apply padding)
 */
void ascon_xof_finalize(ascon_state *state) {
  /* Apply padding: XOR 0x80 at current position */
  state->s.x0 ^= ASCON_PAD(state->pos);
  ascon_p12(&state->s);
  state->pos = 0;
  state->phase = 1;
}

/*
 * Squeeze output from Ascon-XOF state (incremental)
 */
void ascon_xof_squeeze(uint8_t *out, size_t outlen, ascon_state *state) {
  size_t i;
  
  /* If we have remaining bytes in current block */
  if (state->pos > 0) {
    while (state->pos < ASCON_XOF_RATE && outlen > 0) {
      *out = ASCON_GETBYTE(state->s.x0, state->pos);
      out++;
      state->pos++;
      outlen--;
    }
    
    if (state->pos == ASCON_XOF_RATE && outlen > 0) {
      ascon_p12(&state->s);
      state->pos = 0;
    }
  }
  
  /* Squeeze full blocks */
  while (outlen >= ASCON_XOF_RATE) {
    ascon_storebytes(out, state->s.x0, ASCON_XOF_RATE);
    ascon_p12(&state->s);
    out += ASCON_XOF_RATE;
    outlen -= ASCON_XOF_RATE;
  }
  
  /* Squeeze remaining bytes */
  for (i = 0; i < outlen; i++) {
    out[i] = ASCON_GETBYTE(state->s.x0, i);
  }
  state->pos = (unsigned int)outlen;
}

/*
 * Absorb once and finalize (convenience function)
 */
void ascon_xof_absorb_once(ascon_state *state, const uint8_t *in, size_t inlen) {
  ascon_xof_init(state);
  ascon_xof_absorb(state, in, inlen);
  ascon_xof_finalize(state);
}

/*
 * Squeeze full blocks (nblocks * ASCON_XOF_RATE bytes)
 */
void ascon_xof_squeezeblocks(uint8_t *out, size_t nblocks, ascon_state *state) {
  size_t i;
  
  for (i = 0; i < nblocks; i++) {
    ascon_storebytes(out, state->s.x0, ASCON_XOF_RATE);
    ascon_p12(&state->s);
    out += ASCON_XOF_RATE;
  }
  state->pos = 0;
}

/*
 * One-shot Ascon-XOF: absorb input and squeeze output
 */
void ascon_xof(uint8_t *out, size_t outlen, const uint8_t *in, size_t inlen) {
  ascon_state state;
  
  ascon_xof_absorb_once(&state, in, inlen);
  ascon_xof_squeeze(out, outlen, &state);
}

/*
 * Ascon-Hash: 32-byte output (replaces SHA3-256)
 * Uses ASCON_HASH_IV which produces fixed 32-byte output
 */
void ascon_hash_256(uint8_t h[32], const uint8_t *in, size_t inlen) {
  ascon_permutation_state_t s;
  size_t len = inlen;
  
  /* Initialize with Hash IV */
  s.x0 = ASCON_HASH_IV;
  s.x1 = 0;
  s.x2 = 0;
  s.x3 = 0;
  s.x4 = 0;
  ascon_p12(&s);
  
  /* Absorb full blocks */
  while (len >= ASCON_HASH_RATE) {
    s.x0 ^= ascon_loadbytes(in, ASCON_HASH_RATE);
    ascon_p12(&s);
    in += ASCON_HASH_RATE;
    len -= ASCON_HASH_RATE;
  }
  
  /* Absorb final block with padding */
  s.x0 ^= ascon_loadbytes(in, (int)len);
  s.x0 ^= ASCON_PAD(len);
  ascon_p12(&s);
  
  /* Squeeze 32 bytes (4 blocks of 8 bytes) */
  ascon_storebytes(h, s.x0, 8);
  ascon_p12(&s);
  ascon_storebytes(h + 8, s.x0, 8);
  ascon_p12(&s);
  ascon_storebytes(h + 16, s.x0, 8);
  ascon_p12(&s);
  ascon_storebytes(h + 24, s.x0, 8);
}

/*
 * Ascon-XOF with 64-byte output (replaces SHA3-512)
 * Uses XOF mode to squeeze 64 bytes
 */
void ascon_hash_512(uint8_t h[64], const uint8_t *in, size_t inlen) {
  ascon_state state;
  
  ascon_xof_absorb_once(&state, in, inlen);
  ascon_xof_squeeze(h, 64, &state);
}
