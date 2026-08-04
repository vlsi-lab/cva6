// AES-128-CTR, a thin keystream wrapper around the shared aes128_block.h
// single-block interface. Identical source on both the software and tightly
// trees -- only the linked aes128_block implementation differs. Encrypt and
// decrypt are the same operation (XOR with the keystream), so only one
// entry point is exposed.

#ifndef __AES_CTR_H__
#define __AES_CTR_H__

#include <stdint.h>
#include <stddef.h>

// buf is encrypted/decrypted in place, nbytes need not be a multiple of 16.
// counter_block is the initial 128-bit counter, incremented as a full
// 128-bit big-endian integer (NIST SP 800-38A convention) once per 16-byte
// keystream block -- not GCM's 32-bit-wraparound counter (see aes_gcm.c,
// which implements its own counter for that reason).
void aes128_ctr_crypt(const uint8_t key[16], const uint8_t counter_block[16],
                       uint8_t *buf, size_t nbytes);

#endif
