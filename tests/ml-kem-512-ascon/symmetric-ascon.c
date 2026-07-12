/*
 * Kyber symmetric primitives using Ascon
 * 
 * This file replaces symmetric-shake.c, using Ascon-XOF instead of SHAKE
 * 
 * Mappings:
 *   - kyber_shake128_absorb -> kyber_ascon_xof_absorb (XOF for sampling)
 *   - kyber_shake256_prf -> kyber_ascon_prf (PRF for noise generation)
 *   - kyber_shake256_rkprf -> kyber_ascon_rkprf (PRF for re-encapsulation)
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "params.h"
#include "symmetric.h"
#include "ascon.h"

/*************************************************
* Name:        kyber_ascon_xof_absorb
*
* Description: Absorb step of the Ascon-XOF specialized for the Kyber context.
*              This replaces kyber_shake128_absorb.
*
* Arguments:   - ascon_state *state: pointer to (uninitialized) output Ascon state
*              - const uint8_t *seed: pointer to KYBER_SYMBYTES input to absorb
*              - uint8_t x: additional byte of input (matrix position)
*              - uint8_t y: additional byte of input (matrix position)
**************************************************/
void kyber_ascon_xof_absorb(ascon_state *state,
                            const uint8_t seed[KYBER_SYMBYTES],
                            uint8_t x,
                            uint8_t y)
{
  uint8_t extseed[KYBER_SYMBYTES + 2];

  memcpy(extseed, seed, KYBER_SYMBYTES);
  extseed[KYBER_SYMBYTES + 0] = x;
  extseed[KYBER_SYMBYTES + 1] = y;

  ascon_xof_absorb_once(state, extseed, sizeof(extseed));
}

/*************************************************
* Name:        kyber_ascon_prf
*
* Description: Usage of Ascon-XOF as a PRF, concatenates secret and public input
*              and then generates outlen bytes of output.
*              This replaces kyber_shake256_prf.
*
* Arguments:   - uint8_t *out: pointer to output
*              - size_t outlen: number of requested output bytes
*              - const uint8_t *key: pointer to the key (of length KYBER_SYMBYTES)
*              - uint8_t nonce: single-byte nonce (public PRF input)
**************************************************/
void kyber_ascon_prf(uint8_t *out, size_t outlen, const uint8_t key[KYBER_SYMBYTES], uint8_t nonce)
{
  uint8_t extkey[KYBER_SYMBYTES + 1];

  memcpy(extkey, key, KYBER_SYMBYTES);
  extkey[KYBER_SYMBYTES] = nonce;

  ascon_xof(out, outlen, extkey, sizeof(extkey));
}

/*************************************************
* Name:        kyber_ascon_rkprf
*
* Description: Usage of Ascon-XOF as a PRF for re-encapsulation key derivation.
*              Concatenates secret key and ciphertext input, then generates
*              KYBER_SSBYTES bytes of output.
*              This replaces kyber_shake256_rkprf.
*
* Arguments:   - uint8_t *out: pointer to output (KYBER_SSBYTES bytes)
*              - const uint8_t *key: pointer to the key (of length KYBER_SYMBYTES)
*              - const uint8_t *input: pointer to ciphertext (KYBER_CIPHERTEXTBYTES)
**************************************************/
void kyber_ascon_rkprf(uint8_t out[KYBER_SSBYTES], const uint8_t key[KYBER_SYMBYTES], const uint8_t input[KYBER_CIPHERTEXTBYTES])
{
  ascon_state s;

  ascon_xof_init(&s);
  ascon_xof_absorb(&s, key, KYBER_SYMBYTES);
  ascon_xof_absorb(&s, input, KYBER_CIPHERTEXTBYTES);
  ascon_xof_finalize(&s);
  ascon_xof_squeeze(out, KYBER_SSBYTES, &s);
}
