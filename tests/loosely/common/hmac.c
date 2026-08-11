// HMAC (RFC 2104) with SHA3-256, built on sha3_256() from fips202.h.
// Block size B = 136 bytes (SHA3-256's rate -- matches SHA3_256_RATE and the
// convention used by common HMAC-SHA3 implementations, e.g. Python's hmac
// module via hashlib.sha3_256().block_size). Identical source on both the
// software and tightly trees.

#include <string.h>
#include "hmac.h"
#include "fips202.h"

#define HMAC_BLOCK_SIZE SHA3_256_RATE  // 136

void hmac_sha3_256(uint8_t out[32],
                    const uint8_t *key, size_t keylen,
                    const uint8_t *msg, size_t msglen)
{
  uint8_t k[HMAC_BLOCK_SIZE];
  uint8_t ipad_block[HMAC_BLOCK_SIZE];
  uint8_t opad_block[HMAC_BLOCK_SIZE];
  uint8_t inner_digest[32];

  memset(k, 0, sizeof(k));
  if (keylen > HMAC_BLOCK_SIZE) {
    sha3_256(k, key, keylen);  // K' = H(K), zero-padded to block size (already zeroed above)
  } else {
    memcpy(k, key, keylen);
  }

  for (size_t i = 0; i < HMAC_BLOCK_SIZE; i++) {
    ipad_block[i] = k[i] ^ 0x36;
    opad_block[i] = k[i] ^ 0x5c;
  }

  // inner = H((K' xor ipad) || msg)
  // sha3_256() only exposes a non-incremental, single-buffer API, so this
  // uses the shake256_* incremental primitives directly instead (SHA3-256's
  // rate equals SHAKE256_RATE, 136; only the domain byte differs, 0x06 vs
  // SHAKE's 0x1F) to absorb the two concatenated pieces without copying them
  // into one buffer first.
  {
    keccak_state state;
    shake256_init(&state);
    shake256_absorb(&state, ipad_block, HMAC_BLOCK_SIZE);
    shake256_absorb(&state, msg, msglen);
    shake256_finalize_domain(&state, 0x06);
    shake256_squeeze(inner_digest, 32, &state);
  }

  // out = H((K' xor opad) || inner)
  {
    keccak_state state;
    shake256_init(&state);
    shake256_absorb(&state, opad_block, HMAC_BLOCK_SIZE);
    shake256_absorb(&state, inner_digest, 32);
    shake256_finalize_domain(&state, 0x06);
    shake256_squeeze(out, 32, &state);
  }
}
