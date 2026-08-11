// AES-128-XTS (IEEE 1619 / NIST SP 800-38E), built on the shared
// aes128_block.h single-block interface. Identical source on both the
// software and tightly trees. Whole-128-bit-block counts only within one
// data unit (sector) -- no ciphertext stealing for a partial final block,
// same simplification aes_cbc.c already makes for CBC.
//
// The tweak-doubling GF(2^128) math here is XTS's own convention (a
// little-endian bit order, distinct from GHASH's MSB-first convention in
// ghash.h) -- kept local to this file rather than shared with ghash.c to
// keep the two field-math implementations visibly distinct.

#ifndef __AES_XTS_H__
#define __AES_XTS_H__

#include <stdint.h>
#include <stddef.h>

// key1 encrypts data, key2 encrypts the tweak. sector is the 128-bit data
// unit number (represented internally as little-endian, per the spec).
// buf (nblocks * 16 bytes) is encrypted/decrypted in place.
void aes128_xts_encrypt(const uint8_t key1[16], const uint8_t key2[16],
                         uint64_t sector, uint8_t *buf, size_t nblocks);
void aes128_xts_decrypt(const uint8_t key1[16], const uint8_t key2[16],
                         uint64_t sector, uint8_t *buf, size_t nblocks);

#endif
