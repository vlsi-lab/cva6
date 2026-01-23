///////////////////////////////////////////////////////////////////////////////////////
//                                                                                   //
// Auth: Alessandra Dolmeta, Valeria Piscopo - Politecnico di Torino                 //
// Date: September 2025                                                              //
// Desc: Entry point for testing the ML-DSA implementation using input and output    //
//       test vector coming from NIST                                                //
//                                                                                   //
///////////////////////////////////////////////////////////////////////////////////////




#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "api.h"

#include "encoding.h"
#include "uart.h"

#include "test_vectors_shake256_192f_robust.h"


#define TEST_KEY  1
#define TEST_SIGN  1
#define TEST_SIGN_OPEN 1

#define MLEN_KAT 33
uint8_t keypair_rnd[CRYPTO_SEEDBYTES];
uint8_t signature_rnd[SPX_N];

#define CRYPTO_SECRETKEYBYTES SPX_SK_BYTES
#define CRYPTO_PUBLICKEYBYTES SPX_PK_BYTES
#define CRYPTO_BYTES SPX_BYTES
#define CRYPTO_SEEDBYTES 3*SPX_N

void printVect(char* name, uint8_t* buf, size_t size) {
    printf("%s = ", name);
    for (int i=0; i<size; i++){
        printf("%02X", buf[i]);
    }
    printf("\n");
}

int main(void)
{

    uint8_t sk[CRYPTO_SECRETKEYBYTES];
    uint8_t pk[CRYPTO_PUBLICKEYBYTES];

    uint8_t m[MLEN_KAT];
    uint8_t sm[MLEN_KAT + CRYPTO_BYTES];
    uint8_t m1[MLEN_KAT + CRYPTO_BYTES];

    unsigned int cycles;
        
    unsigned long long  mlen, smlen, mlen1;

    char test_str[50] = "Testing";
    #if TEST_KEY
        strcat(test_str," keypair");
    #endif
    #if TEST_SIGN
        strcat(test_str," sign.");
    #endif
    #if TEST_SIGN_OPEN
        strcat(test_str," sign_open.");
    #endif
        printf("%s\n", test_str);

    //************************************************* 
    // KEY
    //*************************************************

    #if TEST_KEY
        // Filling coin vector with indcpa_keypair and kem_keypair seeds
        memcpy(keypair_rnd , TVEC_IN_SIGN_KEYPAIR, 72);

        clear_csr(mcountinhibit, 1);
        write_csr(mcycle, 0);
        crypto_sign_keypair(pk, sk, keypair_rnd);
        cycles = read_csr(mcycle);
        print_uart("Number of clock cycles for crypto_sign_keypair: ");
        print_uart_dec(cycles);
        print_uart("\n");


        if(memcmp(pk, TVEC_OUT_PK, CRYPTO_PUBLICKEYBYTES)) { printf("ERROR: PK mismatch\n"); }
        if(memcmp(sk, TVEC_OUT_SK, CRYPTO_SECRETKEYBYTES)) { printf("ERROR: SK mismatch\n");}
        //printVect("pk", pk, CRYPTO_PUBLICKEYBYTES);
        //printVect("sk", sk, CRYPTO_SECRETKEYBYTES);
    #endif /* TEST_KEY */

    //************************************************* 
    // SIGN
    //*************************************************
    #if TEST_SIGN
        // Setting up Input test vectors
        memcpy(m, TVEC_IN_M_SIGN, MLEN_KAT);
        memcpy(signature_rnd , TVEC_IN_SIGN_SIGNATURE, SPX_N);

        #if TEST_KEY == 0
          // In case we do not generate PK in this test we take it from the test vectors
          memcpy(sk, TVEC_OUT_SK, CRYPTO_SECRETKEYBYTES);
        #endif /* TEST_KEY */

        write_csr(mcycle, 0);

        crypto_sign(sm, &smlen, m, MLEN_KAT, sk, signature_rnd);
        cycles = read_csr(mcycle);
        print_uart("Number of clock cycles for crypto_sign: ");
        print_uart_dec(cycles);
        print_uart("\n");

        if(memcmp(sm, TVEC_IN_SM_SIGN, SPX_BYTES)) { printf("ERROR: SM mismatch\n");}
        //printf("mlen1: %llu\n", SPX_BYTES);
        //printf("sm: ");
        //for (int i = 0; i < SPX_BYTES; i++) {
        //    printf("%02x", sm[i]);
        //}
        //printf("\n");

    #endif /* TEST_SIGN */
    
    //************************************************* 
    // IGN_OPEN
    //*************************************************
    #if TEST_SIGN_OPEN

        #if TEST_KEY == 0
          // In case we do not generate PK in this test we take it from the test vectors
          memcpy(pk, TVEC_OUT_PK, CRYPTO_PUBLICKEYBYTES);
        #endif /* TEST_KEY */

        #if TEST_SIGN == 0
          memcpy(sm, TVEC_IN_SM_SIGN, 35697);
        #endif /* TEST_SIGN */
      
        write_csr(mcycle, 0);

        crypto_sign_open(m1, &mlen1, sm, 35697, pk);
        cycles = read_csr(mcycle);
        print_uart("Number of clock cycles for crypto_sign_open: ");
        print_uart_dec(cycles);
        print_uart("\n");
        
        if(memcmp(m1, TVEC_IN_M_SIGN, MLEN_KAT)) { printf("ERROR: M mismatch\n");}

    #endif /* TEST_SIGN_OPEN */
    
    printf("OK\n");

    printf("Test Successful\n");

    return 0;


}

