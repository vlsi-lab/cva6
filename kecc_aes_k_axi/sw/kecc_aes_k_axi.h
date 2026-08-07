// kecc_aes_k_axi (v2) Accelerator IP - Loosely
// Bare-metal MMIO driver for the AXI-memory-mapped unified AES/Keccak
// accelerator (kecc_aes_k_axi_top.sv). No OS, direct volatile register
// access -- same style as tests/tightly/common's ISE-backed drivers and
// the sibling keccak-only AXI IP's tests/keccak64/keccak_axi.c.
//
// Base address: KeccAesAxiBase is already reserved in
// corev_apu/tb/ariane_soc_pkg.sv (KeccAesAxi peripheral, 64'h5000_0000) by a
// separate address-map task -- KECC_AES_K_AXI_BASE below mirrors that value
// as an overridable #define (define it before including this header, or
// pass -DKECC_AES_K_AXI_BASE=... on the command line, to build against a
// different address map without touching this file).

#ifndef __KECC_AES_K_AXI_H__
#define __KECC_AES_K_AXI_H__

#include <stdint.h>

#ifndef KECC_AES_K_AXI_BASE
#define KECC_AES_K_AXI_BASE 0x50000000UL
#endif

// AES: keylen256 selects CTRL.KEYLEN (0 = 128-bit key, 1 = 256-bit key).
// key[] must always be 32 bytes; for a 128-bit key, only the first 16
// bytes are used (bytes 16-31 are don't-care).
void kecc_aes_k_axi_aes_encrypt_block(const uint8_t key[32], int keylen256,
                                       const uint8_t block_in[16], uint8_t block_out[16]);
void kecc_aes_k_axi_aes_decrypt_block(const uint8_t key[32], int keylen256,
                                       const uint8_t block_in[16], uint8_t block_out[16]);

// Keccak-f[1600] permutation: state_in/state_out are 200 bytes (25 * 64-bit
// lanes, little-endian within each lane -- same convention as
// tests/keccak64/keccak_full.c's uint64_t[25] state). state_in and
// state_out may alias the same buffer.
void kecc_aes_k_axi_keccak_permute(const uint8_t state_in[200], uint8_t state_out[200]);

// Scrub state + AES key schedule to 0 (CTRL.ZEROIZE), and wait until the
// core reports ready again.
void kecc_aes_k_axi_zeroize(void);

#endif
