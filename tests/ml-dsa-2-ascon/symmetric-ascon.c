/*
 * Dilithium symmetric primitives using Ascon
 * 
 * This file replaces symmetric-shake.c, using Ascon-XOF instead of SHAKE
 * 
 * Mappings:
 *   - dilithium_shake128_stream_init -> dilithium_ascon_stream128_init
 *   - dilithium_shake256_stream_init -> dilithium_ascon_stream256_init
 */

#include <stdint.h>
#include "params.h"
#include "symmetric.h"
#include "ascon.h"

/*************************************************
* Name:        dilithium_ascon_stream128_init
*
* Description: Absorb step of the Ascon-XOF specialized for the Dilithium context.
*              This replaces dilithium_shake128_stream_init.
*              Concatenates seed and nonce and initializes XOF state.
*
* Arguments:   - ascon_state *state: pointer to (uninitialized) output Ascon state
*              - const uint8_t *seed: pointer to SEEDBYTES input to absorb
*              - uint16_t nonce: 2-byte nonce
**************************************************/
void dilithium_ascon_stream128_init(ascon_state *state,
                                     const uint8_t seed[SEEDBYTES],
                                     uint16_t nonce)
{
  uint8_t t[2];
  t[0] = nonce;
  t[1] = nonce >> 8;

  shake128_init(state);
  shake128_absorb(state, seed, SEEDBYTES);
  shake128_absorb(state, t, 2);
  shake128_finalize(state);
}

/*************************************************
* Name:        dilithium_ascon_stream256_init
*
* Description: Absorb step of the Ascon-XOF specialized for the Dilithium context.
*              This replaces dilithium_shake256_stream_init.
*              Concatenates seed and nonce and initializes XOF state.
*
* Arguments:   - ascon_state *state: pointer to (uninitialized) output Ascon state
*              - const uint8_t *seed: pointer to CRHBYTES input to absorb
*              - uint16_t nonce: 2-byte nonce
**************************************************/
void dilithium_ascon_stream256_init(ascon_state *state,
                                     const uint8_t seed[CRHBYTES],
                                     uint16_t nonce)
{
  uint8_t t[2];
  t[0] = nonce;
  t[1] = nonce >> 8;

  shake256_init(state);
  shake256_absorb(state, seed, CRHBYTES);
  shake256_absorb(state, t, 2);
  shake256_finalize(state);
}
