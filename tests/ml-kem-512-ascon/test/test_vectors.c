/* Deterministic randombytes using Ascon-XOF */
/* Adapted from test_vectors.c for Kyber-Ascon */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include "../kem.h"
#include "../randombytes.h"
#include "../ascon.h"

#define NTESTS 10000

/* Ascon RNG state - initialized with empty input */
static ascon_state rngstate;
static int rng_initialized = 0;

void randombytes(uint8_t *x, size_t xlen)
{
  if (!rng_initialized) {
    /* Initialize with absorbing empty string and finalize */
    ascon_xof_absorb_once(&rngstate, NULL, 0);
    rng_initialized = 1;
  }
  ascon_xof_squeeze(x, xlen, &rngstate);
}

int main(void)
{
  unsigned int i,j;
  uint8_t pk[CRYPTO_PUBLICKEYBYTES];
  uint8_t sk[CRYPTO_SECRETKEYBYTES];
  uint8_t ct[CRYPTO_CIPHERTEXTBYTES];
  uint8_t key_a[CRYPTO_BYTES];
  uint8_t key_b[CRYPTO_BYTES];

  for(i=0;i<NTESTS;i++) {
    // Key-pair generation
    crypto_kem_keypair(pk, sk);
    printf("Public Key: ");
    for(j=0;j<CRYPTO_PUBLICKEYBYTES;j++)
      printf("%02x",pk[j]);
    printf("\n");
    printf("Secret Key: ");
    for(j=0;j<CRYPTO_SECRETKEYBYTES;j++)
      printf("%02x",sk[j]);
    printf("\n");

    // Encapsulation
    crypto_kem_enc(ct, key_b, pk);
    printf("Ciphertext: ");
    for(j=0;j<CRYPTO_CIPHERTEXTBYTES;j++)
      printf("%02x",ct[j]);
    printf("\n");
    printf("Shared Secret B: ");
    for(j=0;j<CRYPTO_BYTES;j++)
      printf("%02x",key_b[j]);
    printf("\n");

    // Decapsulation
    crypto_kem_dec(key_a, ct, sk);
    printf("Shared Secret A: ");
    for(j=0;j<CRYPTO_BYTES;j++)
      printf("%02x",key_a[j]);
    printf("\n");

    for(j=0;j<CRYPTO_BYTES;j++) {
      if(key_a[j] != key_b[j]) {
        fprintf(stderr, "ERROR\n");
        return -1;
      }
    }

    // Decapsulation of invalid (random) ciphertexts
    randombytes(ct, KYBER_CIPHERTEXTBYTES); 
    crypto_kem_dec(key_a, ct, sk);
    printf("Pseudorandom shared Secret A: ");
    for(j=0;j<CRYPTO_BYTES;j++)
      printf("%02x",key_a[j]);
    printf("\n");
  }

  return 0;
}
