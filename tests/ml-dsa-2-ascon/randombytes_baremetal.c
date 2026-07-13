/*
 * Bare-metal randombytes() for running ML-DSA on the cva6 testharness.
 *
 * The reference randombytes.c reads /dev/urandom, which doesn't exist
 * without an OS. crypto_sign_keypair() and crypto_sign_signature() call
 * randombytes() unconditionally (unlike ML-KEM, ML-DSA exposes no _derand
 * entry point), so a working substitute is required just to run at all.
 *
 * This is a fixed-seed splitmix64 PRNG: not an entropy source, only a
 * deterministic byte stream. The fixed seed also means the with-coprocessor
 * and without-coprocessor runs generate the exact same keys/message/signing
 * randomness, so their cycle counts are directly comparable.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "randombytes.h"

static uint64_t prng_state = 0x9E3779B97F4A7C15ULL;

static uint64_t splitmix64_next(void) {
  uint64_t z = (prng_state += 0x9E3779B97F4A7C15ULL);
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
  return z ^ (z >> 31);
}

void randombytes(uint8_t *out, size_t outlen) {
  while (outlen >= 8) {
    uint64_t r = splitmix64_next();
    memcpy(out, &r, 8);
    out += 8;
    outlen -= 8;
  }
  if (outlen > 0) {
    uint64_t r = splitmix64_next();
    memcpy(out, &r, outlen);
  }
}
