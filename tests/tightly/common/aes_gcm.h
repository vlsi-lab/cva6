// AES-128-GCM (NIST SP 800-38D), built on the shared aes128_block.h
// single-block interface plus ghash.h. Identical source on both the
// software and tightly trees. 96-bit (12-byte) IV only -- the common case;
// other IV lengths need an extra GHASH-of-IV step this implementation does
// not perform.

#ifndef __AES_GCM_H__
#define __AES_GCM_H__

#include <stdint.h>
#include <stddef.h>

// buf is encrypted in place (len need not be a multiple of 16); tag is
// always 16 bytes.
void aes128_gcm_encrypt(const uint8_t key[16], const uint8_t iv[12],
                         const uint8_t *aad, size_t aad_len,
                         uint8_t *buf, size_t len, uint8_t tag[16]);

// buf is decrypted in place regardless of tag outcome (same as any
// streaming AEAD decrypt -- the caller must discard buf on a nonzero
// return). Returns 0 if the computed tag matches `tag`, nonzero otherwise.
int aes128_gcm_decrypt(const uint8_t key[16], const uint8_t iv[12],
                        const uint8_t *aad, size_t aad_len,
                        uint8_t *buf, size_t len, const uint8_t tag[16]);

#endif
