// HMAC (RFC 2104) using SHA3-256 as the underlying hash, built on sha3_256()
// from fips202.h. Identical source on both the software and tightly trees.

#ifndef __HMAC_H__
#define __HMAC_H__

#include <stdint.h>
#include <stddef.h>

// out must have room for 32 bytes (SHA3-256 digest size).
void hmac_sha3_256(uint8_t out[32],
                    const uint8_t *key, size_t keylen,
                    const uint8_t *msg, size_t msglen);

#endif
