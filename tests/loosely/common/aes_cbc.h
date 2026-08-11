// AES-128-CBC encrypt/decrypt, a thin chaining wrapper around the shared
// aes128_block.h single-block interface. Identical source on both the
// software and tightly trees -- only the linked aes128_block implementation
// differs.

#ifndef __AES_CBC_H__
#define __AES_CBC_H__

#include <stdint.h>
#include <stddef.h>

// nblocks 16-byte blocks; buf is encrypted/decrypted in place.
void aes128_cbc_encrypt(const uint8_t key[16], const uint8_t iv[16],
                         uint8_t *buf, size_t nblocks);
void aes128_cbc_decrypt(const uint8_t key[16], const uint8_t iv[16],
                         uint8_t *buf, size_t nblocks);

#endif
