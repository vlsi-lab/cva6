#ifndef API_H
#define API_H

#include <stdint.h>

#define pqcrystals_kyber512_SECRETKEYBYTES 1632
#define pqcrystals_kyber512_PUBLICKEYBYTES 800
#define pqcrystals_kyber512_CIPHERTEXTBYTES 768
#define pqcrystals_kyber512_KEYPAIRCOINBYTES 64
#define pqcrystals_kyber512_ENCCOINBYTES 32
#define pqcrystals_kyber512_BYTES 32

#define pqcrystals_kyber512_ref_SECRETKEYBYTES pqcrystals_kyber512_SECRETKEYBYTES
#define pqcrystals_kyber512_ref_PUBLICKEYBYTES pqcrystals_kyber512_PUBLICKEYBYTES
#define pqcrystals_kyber512_ref_CIPHERTEXTBYTES pqcrystals_kyber512_CIPHERTEXTBYTES
#define pqcrystals_kyber512_ref_KEYPAIRCOINBYTES pqcrystals_kyber512_KEYPAIRCOINBYTES
#define pqcrystals_kyber512_ref_ENCCOINBYTES pqcrystals_kyber512_ENCCOINBYTES
#define pqcrystals_kyber512_ref_BYTES pqcrystals_kyber512_BYTES

int pqcrystals_kyber512_ref_keypair_derand(uint8_t *pk, uint8_t *sk, const uint8_t *coins);
int pqcrystals_kyber512_ref_keypair(uint8_t *pk, uint8_t *sk);
int pqcrystals_kyber512_ref_enc_derand(uint8_t *ct, uint8_t *ss, const uint8_t *pk, const uint8_t *coins);
int pqcrystals_kyber512_ref_enc(uint8_t *ct, uint8_t *ss, const uint8_t *pk);
int pqcrystals_kyber512_ref_dec(uint8_t *ss, const uint8_t *ct, const uint8_t *sk);

#endif
