// KMAC256 (NIST SP 800-185), built on top of shake256() from fips202.h.
// Identical source on the software and tightly trees -- it only calls the
// shared hash interface, so the underlying permutation (software vs.
// coprocessor) is the only thing that differs between the two builds.

#ifndef __KMAC_H__
#define __KMAC_H__

#include <stdint.h>
#include <stddef.h>

// KMAC256(K, X, L, S) -> out[outlen]
void kmac256(uint8_t *out, size_t outlen,
             const uint8_t *key, size_t keylen,
             const uint8_t *in, size_t inlen,
             const uint8_t *custom, size_t customlen);

#endif
