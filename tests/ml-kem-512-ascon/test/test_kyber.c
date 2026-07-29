#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "../kem.h"
#include "../randombytes.h"

#define NTESTS 1000

// Helper function to print hex values
static void print_hex(const char* label, const uint8_t* data, size_t len) {
  printf("%s: ", label);
  for(size_t i = 0; i < len && i < 32; i++) {  // Print first 32 bytes
    printf("%02x", data[i]);
  }
  if(len > 32) printf("...");
  printf("\n");
}

static int test_keys(int verbose)
{
  uint8_t pk[CRYPTO_PUBLICKEYBYTES];
  uint8_t sk[CRYPTO_SECRETKEYBYTES];
  uint8_t ct[CRYPTO_CIPHERTEXTBYTES];
  uint8_t key_a[CRYPTO_BYTES];
  uint8_t key_b[CRYPTO_BYTES];

  //Alice generates a public key
  crypto_kem_keypair(pk, sk);

  //Bob derives a secret key and creates a response
  crypto_kem_enc(ct, key_b, pk);

  //Alice uses Bobs response to get her shared key
  crypto_kem_dec(key_a, ct, sk);

  if(memcmp(key_a, key_b, CRYPTO_BYTES)) {
    printf("ERROR keys\n");
    return 1;
  }
  
  // Print keys to verify they match (only if verbose mode)
  if(verbose) {
    printf("\n=== Key Exchange Verification ===\n");
    print_hex("Public Key (pk)", pk, CRYPTO_PUBLICKEYBYTES);
    print_hex("Secret Key (sk)", sk, CRYPTO_SECRETKEYBYTES);
    print_hex("Shared Key A (Alice)", key_a, CRYPTO_BYTES);
    print_hex("Shared Key B (Bob)", key_b, CRYPTO_BYTES);
    
    if(memcmp(key_a, key_b, CRYPTO_BYTES) == 0) {
      printf("✓ SUCCESS: Keys match! Key exchange successful.\n");
    }
    printf("=================================\n\n");
  }

  return 0;
}

static int test_invalid_sk_a(void)
{
  uint8_t pk[CRYPTO_PUBLICKEYBYTES];
  uint8_t sk[CRYPTO_SECRETKEYBYTES];
  uint8_t ct[CRYPTO_CIPHERTEXTBYTES];
  uint8_t key_a[CRYPTO_BYTES];
  uint8_t key_b[CRYPTO_BYTES];

  //Alice generates a public key
  crypto_kem_keypair(pk, sk);

  //Bob derives a secret key and creates a response
  crypto_kem_enc(ct, key_b, pk);

  //Replace secret key with random values
  randombytes(sk, CRYPTO_SECRETKEYBYTES);

  //Alice uses Bobs response to get her shared key
  crypto_kem_dec(key_a, ct, sk);

  if(!memcmp(key_a, key_b, CRYPTO_BYTES)) {
    printf("ERROR invalid sk\n");
    return 1;
  }

  return 0;
}

static int test_invalid_ciphertext(void)
{
  uint8_t pk[CRYPTO_PUBLICKEYBYTES];
  uint8_t sk[CRYPTO_SECRETKEYBYTES];
  uint8_t ct[CRYPTO_CIPHERTEXTBYTES];
  uint8_t key_a[CRYPTO_BYTES];
  uint8_t key_b[CRYPTO_BYTES];
  uint8_t b;
  size_t pos;

  do {
    randombytes(&b, sizeof(uint8_t));
  } while(!b);
  randombytes((uint8_t *)&pos, sizeof(size_t));

  //Alice generates a public key
  crypto_kem_keypair(pk, sk);

  //Bob derives a secret key and creates a response
  crypto_kem_enc(ct, key_b, pk);

  //Change some byte in the ciphertext (i.e., encapsulated key)
  ct[pos % CRYPTO_CIPHERTEXTBYTES] ^= b;

  //Alice uses Bobs response to get her shared key
  crypto_kem_dec(key_a, ct, sk);

  if(!memcmp(key_a, key_b, CRYPTO_BYTES)) {
    printf("ERROR invalid ciphertext\n");
    return 1;
  }

  return 0;
}

int main(void)
{
  unsigned int i;
  int r;

  printf("Testing Kyber KEM implementation...\n");
  printf("Running %d test iterations\n\n", NTESTS);

  for(i=0;i<NTESTS;i++) {
    // Print detailed output only for the first test
    r  = test_keys(i == 0);
    r |= test_invalid_sk_a();
    r |= test_invalid_ciphertext();
    if(r)
      return 1;
    
    // Progress indicator every 100 tests
    if((i+1) % 100 == 0) {
      printf("Completed %d/%d tests...\n", i+1, NTESTS);
    }
  }

  printf("\n✓ All %d tests passed successfully!\n\n", NTESTS);
  printf("CRYPTO_SECRETKEYBYTES:  %d\n",CRYPTO_SECRETKEYBYTES);
  printf("CRYPTO_PUBLICKEYBYTES:  %d\n",CRYPTO_PUBLICKEYBYTES);
  printf("CRYPTO_CIPHERTEXTBYTES: %d\n",CRYPTO_CIPHERTEXTBYTES);

  return 0;
}
