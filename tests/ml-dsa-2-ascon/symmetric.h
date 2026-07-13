/*
 * Dilithium symmetric primitives header - Ascon version
 * 
 * This replaces the FIPS-202 (Keccak/SHAKE) symmetric primitives with Ascon
 * 
 * Note: Dilithium-Ascon is only designed for Dilithium-2 security level,
 * as Ascon provides 128-bit security primitives.
 */

#ifndef SYMMETRIC_H
#define SYMMETRIC_H

#include <stdint.h>
#include "params.h"

#include "ascon.h"

/* Use Ascon state for stream operations */
typedef ascon_state stream128_state;
typedef ascon_state stream256_state;

/* Dilithium-specific Ascon functions */
#define dilithium_ascon_stream128_init DILITHIUM_NAMESPACE(dilithium_ascon_stream128_init)
void dilithium_ascon_stream128_init(ascon_state *state,
                                     const uint8_t seed[SEEDBYTES],
                                     uint16_t nonce);

#define dilithium_ascon_stream256_init DILITHIUM_NAMESPACE(dilithium_ascon_stream256_init)
void dilithium_ascon_stream256_init(ascon_state *state,
                                     const uint8_t seed[CRHBYTES],
                                     uint16_t nonce);

/* XOF block size for Ascon (8 bytes) */
#define STREAM128_BLOCKBYTES ASCON_XOF_RATE
#define STREAM256_BLOCKBYTES ASCON_XOF_RATE

/* Stream macros - map Dilithium's generic names to Ascon implementations */
#define stream128_init(STATE, SEED, NONCE) \
        dilithium_ascon_stream128_init(STATE, SEED, NONCE)
#define stream128_squeezeblocks(OUT, OUTBLOCKS, STATE) \
        ascon_xof_squeezeblocks(OUT, OUTBLOCKS, STATE)
#define stream256_init(STATE, SEED, NONCE) \
        dilithium_ascon_stream256_init(STATE, SEED, NONCE)
#define stream256_squeezeblocks(OUT, OUTBLOCKS, STATE) \
        ascon_xof_squeezeblocks(OUT, OUTBLOCKS, STATE)

#endif /* SYMMETRIC_H */
