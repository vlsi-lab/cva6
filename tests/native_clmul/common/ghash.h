// GHASH: the GF(2^128) universal hash used by AES-GCM (NIST SP 800-38D).
// Same public interface as tests/software/common/ghash.h and
// tests/tightly/common/ghash.h, but gf128_mul here is implemented on top of
// the RISC-V B-extension's native clmul/clmulh instructions (see
// clmul_native.h) instead of the bit-serial shift-and-xor algorithm.

#ifndef __GHASH_H__
#define __GHASH_H__

#include <stdint.h>
#include <stddef.h>

// out = a * b in GCM's GF(2^128) (reduction polynomial x^128+x^7+x^2+x+1,
// MSB-first bit order per SP 800-38D). out may alias a and/or b.
void gf128_mul(uint8_t out[16], const uint8_t a[16], const uint8_t b[16]);

// GHASH_H(AAD, C): absorbs aad then data (each zero-padded to a 16-byte
// multiple) followed by the 64/64-bit bit-length block, per SP 800-38D
// section 6.4. `data` is normally the ciphertext.
void ghash(const uint8_t H[16], const uint8_t *aad, size_t aad_len,
           const uint8_t *data, size_t data_len, uint8_t out[16]);

#endif
