///////////////////////////////////////////////////////////////////////////////////////
//                                                                                   //
// Auth: Alessandra Dolmeta, Valeria Piscopo - Politecnico di Torino                 //
// Date: September 2025                                                              //
// Desc: Entry point for testing the ML-KEM implementation using input and output    //
//       test vector coming from NIST                                                //
//                                                                                   //
///////////////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>

#include "kem.h"
#include "test_vectors_512.h"
#include "encoding.h"
#include "uart.h"

#define TEST_KEY  1
#define TEST_ENC  1
#define TEST_DEC  1


uint8_t keypair_rnd[2*KYBER_SYMBYTES];
uint8_t encaps_rnd[KYBER_SYMBYTES];

void printVect(char* name, uint8_t* buf, size_t size) {
    print_uart(name);
    for (int i=0; i<size; i++){
        print_uart_hex8(buf[i]);
    }
    print_uart("\n");
}

static uint8_t pk[KYBER_PUBLICKEYBYTES];
static uint8_t sk[KYBER_SECRETKEYBYTES];
static uint8_t ct[KYBER_CIPHERTEXTBYTES];
static uint8_t key_a[KYBER_SSBYTES];
static uint8_t key_b[KYBER_SSBYTES];

int main(void)
{

    unsigned int cycles;

    //************************************************* 
    // KEY
    //*************************************************
    #if TEST_KEY
        // Filling coin vector with indcpa_kem_keypair seeds, obtained from the initialization of randombyte with seed
        memcpy(keypair_rnd , TVEC_IN_KEM_KEYPAIR, KYBER_SYMBYTES*2);
        printVect("keypair_rnd= ", keypair_rnd, KYBER_SYMBYTES*2);
 
        clear_csr(mcountinhibit, 1);
        write_csr(mcycle, 0);
        
        crypto_kem_keypair_derand(pk, sk, keypair_rnd);
        
        cycles = read_csr(mcycle);
        print_uart("Number of clock cycles for crypto_kem_keypair_derand: ");
        print_uart_dec(cycles);
        print_uart("\n");

        if(memcmp(pk, TVEC_OUT_PK, KYBER_PUBLICKEYBYTES)) { print_uart("ERROR: PK mismatch\n");}
        if(memcmp(sk, TVEC_OUT_SK, KYBER_SECRETKEYBYTES)) { print_uart("ERROR: SK mismatch\n");}
    #endif /* TEST_KEY */

    //************************************************* 
    // ENCAPSULATION
    //*************************************************
    #if TEST_ENC
        // Setting up Input test vectors
        memcpy(encaps_rnd, TVEC_IN_KEM_ENC, KYBER_SYMBYTES);

        #if TEST_KEY == 0
            memcpy(pk, TVEC_OUT_PK, KYBER_PUBLICKEYBYTES);
        #endif /* TEST_KEY */

        write_csr(mcycle, 0);
        crypto_kem_enc_derand(ct, key_b, pk, encaps_rnd);
        cycles = read_csr(mcycle);
        print_uart("Number of clock cycles for crypto_kem_enc_derand: ");
        print_uart_dec(cycles);
        print_uart("\n");

        if(memcmp(ct, TVEC_OUT_CT, KYBER_CIPHERTEXTBYTES)) { print_uart("ERROR: CT mismatch\n");}
        if(memcmp(key_b, TVEC_OUT_SS, KYBER_SSBYTES)) { print_uart("ERROR: SS mismatch\n");}
    #endif /* TEST_ENC */

    //************************************************* 
    // DECAPSULATION
    //*************************************************

    #if TEST_DEC
        #if TEST_KEY == 0
            // In case we do not generate SK in this test we take it from the test vectors
            memcpy(sk, TVEC_OUT_SK, KYBER_SECRETKEYBYTES);
        #endif /* TEST_KEY */
        #if TEST_ENC == 0
            // In case we do not generate CT in this test we take it from the test vectors
            memcpy(ct, TVEC_OUT_CT, KYBER_CIPHERTEXTBYTES);
        #endif /* TEST_ENC */

        write_csr(mcycle, 0);
        crypto_kem_dec(key_a, ct, sk);
        cycles = read_csr(mcycle);
        print_uart("Number of clock cycles for crypto_kem_dec: ");
        print_uart_dec(cycles);
        print_uart("\n");

        if(memcmp(key_a, TVEC_OUT_SS, KYBER_SSBYTES)) { print_uart("ERROR: SS mismatch\n");}
    #endif /* TEST_DEC */

    print_uart("OK\n");


    printVect("key_b= ", key_b, KYBER_SSBYTES);
    printVect("key_a= ", key_a, KYBER_SSBYTES);
    printVect("key_r= ", TVEC_OUT_SS, KYBER_SSBYTES);
    print_uart("Test Successful\n");
    

    return 0;
}

