/*
 * Kyber symmetric primitives header - Ascon version
 * 
 * This replaces the FIPS-202 (Keccak/SHAKE) symmetric primitives with Ascon
 * 
 * Note: Kyber-Ascon is only designed for Kyber-512 security level,
 * as Ascon provides 128-bit security primitives.
 */

#ifndef SYMMETRIC_H
#define SYMMETRIC_H

#include <stddef.h>
#include <stdint.h>
#include "params.h"

#include "ascon.h"

/* Use Ascon state for XOF operations */
typedef ascon_state xof_state;

/* XOF block size for Ascon (8 bytes) */
#define XOF_BLOCKBYTES ASCON_XOF_RATE

/*
 * Kyber-specific Ascon functions
 */
#define kyber_ascon_xof_absorb KYBER_NAMESPACE(kyber_ascon_xof_absorb)
void kyber_ascon_xof_absorb(ascon_state *s,
                            const uint8_t seed[KYBER_SYMBYTES],
                            uint8_t x,
                            uint8_t y);

#define kyber_ascon_prf KYBER_NAMESPACE(kyber_ascon_prf)
void kyber_ascon_prf(uint8_t *out, size_t outlen, const uint8_t key[KYBER_SYMBYTES], uint8_t nonce);

#define kyber_ascon_rkprf KYBER_NAMESPACE(kyber_ascon_rkprf)
void kyber_ascon_rkprf(uint8_t out[KYBER_SSBYTES], const uint8_t key[KYBER_SYMBYTES], const uint8_t input[KYBER_CIPHERTEXTBYTES]);

/*
 * Symmetric primitive macros - map Kyber's generic names to Ascon implementations
 * 
 * hash_h:        H function (32-byte hash) - uses Ascon-Hash
 * hash_g:        G function (64-byte hash) - uses Ascon-XOF
 * xof_absorb:    XOF absorb for sampling - uses Ascon-XOF
 * xof_squeezeblocks: XOF squeeze blocks - uses Ascon-XOF
 * prf:           Pseudo-random function - uses Ascon-XOF
 * rkprf:         Re-encapsulation key PRF - uses Ascon-XOF
 */
#define hash_h(OUT, IN, INBYTES) ascon_hash_256(OUT, IN, INBYTES)
#define hash_g(OUT, IN, INBYTES) ascon_hash_512(OUT, IN, INBYTES)
#define xof_absorb(STATE, SEED, X, Y) kyber_ascon_xof_absorb(STATE, SEED, X, Y)
#define xof_squeezeblocks(OUT, OUTBLOCKS, STATE) ascon_xof_squeezeblocks(OUT, OUTBLOCKS, STATE)
#define prf(OUT, OUTBYTES, KEY, NONCE) kyber_ascon_prf(OUT, OUTBYTES, KEY, NONCE)
#define rkprf(OUT, KEY, INPUT) kyber_ascon_rkprf(OUT, KEY, INPUT)

#endif /* SYMMETRIC_H */
