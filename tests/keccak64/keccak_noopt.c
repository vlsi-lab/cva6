// Keccak Accelerator IP - Loosely
// C baseline for Keccak-F permutation 
// Author: Federico Runco
// Partly based on https://github.com/riscv/riscv-crypto/blob/main/benchmarks/sha3/zscrypto_rv64/Keccak.c

#include "inc/uart.h"
#include "encoding.h"

#define ROL64(a, offset) (((a) << (offset)) | ((a) >> (64 - (offset))))
#define ANDN(a, b) (~(a) & (b))

static const uint64_t KeccakP1600RoundConstants[24] =
{
    0x0000000000000001,
    0x0000000000008082,
    0x800000000000808a,
    0x8000000080008000,
    0x000000000000808b,
    0x0000000080000001,
    0x8000000080008081,
    0x8000000000008009,
    0x000000000000008a,
    0x0000000000000088,
    0x0000000080008009,
    0x000000008000000a,
    0x000000008000808b,
    0x800000000000008b,
    0x8000000000008089,
    0x8000000000008003,
    0x8000000000008002,
    0x8000000000000080,
    0x000000000000800a,
    0x800000008000000a,
    0x8000000080008081,
    0x8000000000008080,
    0x0000000080000001,
    0x8000000080008008,
};

static void KeccakF1600_StatePermute(uint64_t *s)
{
    int round, y;

    uint64_t s00, s01, s02, s03, s04;
    uint64_t s05, s06, s07, s08, s09;
    uint64_t s10, s11, s12, s13, s14;
    uint64_t s15, s16, s17, s18, s19;
    uint64_t s20, s21, s22, s23, s24;

    s00 = s[0];
    s01 = s[1];
    s02 = s[2];
    s03 = s[3];
    s04 = s[4];
    s05 = s[5];
    s06 = s[6];
    s07 = s[7];
    s08 = s[8];
    s09 = s[9];
    s10 = s[10];
    s11 = s[11];
    s12 = s[12];
    s13 = s[13];
    s14 = s[14];
    s15 = s[15];
    s16 = s[16];
    s17 = s[17];
    s18 = s[18];
    s19 = s[19];
    s20 = s[20];
    s21 = s[21];
    s22 = s[22];
    s23 = s[23];
    s24 = s[24];

    for(round=0; round<24; round++) {
        uint64_t C0, C1, C2, C3;

        C0 = s00 ^ s05 ^ s10 ^ s15 ^ s20;
        C1 = s01 ^ s06 ^ s11 ^ s16 ^ s21;
        C3 = s04 ^ s09 ^ s14 ^ s19 ^ s24;
        
        C2 = ROL64(C1, 1) ^ C3;

        s00 = s00 ^ C2;
        s05 = s05 ^ C2;
        s10 = s10 ^ C2;
        s15 = s15 ^ C2;
        s20 = s20 ^ C2;
        
        C2 = s02 ^ s07 ^ s12 ^ s17 ^ s22 ;

        C3 = ROL64(C3, 1) ^ C2;
        C2 = ROL64(C2, 1) ^ C0;
             
        s01 = s01 ^ C2;
        s06 = s06 ^ C2;
        s11 = s11 ^ C2;
        s16 = s16 ^ C2;
        s21 = s21 ^ C2;
        
        C2 = s03 ^ s08 ^ s13 ^ s18 ^ s23;
        
        C0 = ROL64(C0, 1) ^ C2;
        C2 = ROL64(C2, 1) ^ C1;
             
        s04 = s04 ^ C0;
        s09 = s09 ^ C0;
        s14 = s14 ^ C0;
        s19 = s19 ^ C0;
        s24 = s24 ^ C0;
             
        s03 = s03 ^ C3;
        s08 = s08 ^ C3;
        s13 = s13 ^ C3;
        s18 = s18 ^ C3;
        s23 = s23 ^ C3;
        
        s02 = s02 ^ C2;
        s07 = s07 ^ C2;
        s12 = s12 ^ C2;
        s17 = s17 ^ C2;
        s22 = s22 ^ C2;
        
        C1    = s05;
        s05 = ROL64(s03,28);
        s03 = ROL64(s18,21);
        s18 = ROL64(s17,15);
        s17 = ROL64(s11,10);
        s11 = ROL64(s07, 6);
        s07 = ROL64(s10, 3);
        s10 = ROL64(s01, 1);
        s01 = ROL64(s06,44);
        s06 = ROL64(s09,20);
        s09 = ROL64(s22,61);
        s22 = ROL64(s14,39);
        s14 = ROL64(s20,18);
        s20 = ROL64(s02,62);
        s02 = ROL64(s12,43);
        s12 = ROL64(s13,25);
        s13 = ROL64(s19, 8);
        s19 = ROL64(s23,56);
        s23 = ROL64(s15,41);
        s15 = ROL64(s04,27);
        s04 = ROL64(s24,14);
        s24 = ROL64(s21, 2);
        s21 = ROL64(s08,55);
        s08 = ROL64(s16,45);
        s16 = ROL64(C1,36);

        C0    = (~s03) & s04;
        s04 = s04 ^ ANDN(s00, s01);
        s01 = s01 ^ ANDN(s02, s03);
        s03 = s03 ^ ANDN(s04, s00);
        s00 = s00 ^ ANDN(s01, s02);
        s02 = s02 ^ (C0              );

        C0    = (~s08) & s09;
        s09 = s09 ^ ANDN(s05, s06);
        s06 = s06 ^ ANDN(s07, s08);
        s08 = s08 ^ ANDN(s09, s05);
        s05 = s05 ^ ANDN(s06, s07);
        s07 = s07 ^ (C0              );

        C0    = (~s13) & s14;
        s14 = s14 ^ ANDN(s10, s11);
        s11 = s11 ^ ANDN(s12, s13);
        s13 = s13 ^ ANDN(s14, s10);
        s10 = s10 ^ ANDN(s11, s12);
        s12 = s12 ^ (C0                );
                     
        C0    = (~s18) & s19;
        s19 = s19 ^ ANDN(s15, s16);
        s16 = s16 ^ ANDN(s17, s18);
        s18 = s18 ^ ANDN(s19, s15);
        s15 = s15 ^ ANDN(s16, s17);
        s17 = s17 ^ (C0                );

        C0    = (~s23) & s24;
        s24 = s24 ^ ANDN(s20, s21);
        s21 = s21 ^ ANDN(s22, s23);
        s23 = s23 ^ ANDN(s24, s20);
        s20 = s20 ^ ANDN(s21, s22);
        s22 = s22 ^ (C0                );
        s00 ^= KeccakP1600RoundConstants[round];
    }

    s[0]  = s00;
    s[1]  = s01;
    s[2]  = s02;
    s[3]  = s03;
    s[4]  = s04;
    s[5]  = s05;
    s[6]  = s06;
    s[7]  = s07;
    s[8]  = s08;
    s[9]  = s09;
    s[10] = s10;
    s[11] = s11;
    s[12] = s12;
    s[13] = s13;
    s[14] = s14;
    s[15] = s15;
    s[16] = s16;
    s[17] = s17;
    s[18] = s18;
    s[19] = s19;
    s[20] = s20;
    s[21] = s21;
    s[22] = s22;
    s[23] = s23;
    s[24] = s24;
}


int main(){
    static uint64_t Din[25], D_expected[25];
    int cycles;
    int errors = 0;

    // Initial state 
    memset(Din, 0, sizeof(Din));
    Din[0]  = 0xEC4AFF517369C667ULL; 
    Din[1]  = 0x00000010ABBACD29ULL; 
    Din[15] = 0x8000000000000000ULL;

    // Expected state after permutation
    D_expected[0]  = 0xE1ADB0E2E7CB8356ULL;
    D_expected[1]  = 0xBB3F5FB8573A5BD7ULL;
    D_expected[2]  = 0xF7CA02A1E9784CC5ULL;
    D_expected[3]  = 0x6E54F25660A4C685ULL;
    D_expected[4]  = 0x77051F83243FCBAAULL;
    D_expected[5]  = 0x6459DB0B4C063DD5ULL;
    D_expected[6]  = 0xE046DE71CB4B81C6ULL;
    D_expected[7]  = 0x94051793DB31F24CULL;
    D_expected[8]  = 0xA13FC86CF16E32DDULL;
    D_expected[9]  = 0xB962FC91B7737708ULL;
    D_expected[10] = 0xD3CA2E7AFA27C801ULL;
    D_expected[11] = 0x53C85108F72A3CCAULL;
    D_expected[12] = 0x73E732CDADF0E783ULL;
    D_expected[13] = 0x8470BD54C4BDD1BFULL;
    D_expected[14] = 0xD10B916F7C8C1F77ULL;
    D_expected[15] = 0x51129474440A2670ULL;
    D_expected[16] = 0x3D77CB49E9960C44ULL;
    D_expected[17] = 0xEC5001EBE4251E39ULL;
    D_expected[18] = 0x77A0EEC5EA4FD653ULL;
    D_expected[19] = 0xEBC86BD47B6773E7ULL;
    D_expected[20] = 0xE77DF6B0128FDC4BULL;
    D_expected[21] = 0x0DB0D48A02F1B12EULL;
    D_expected[22] = 0x241B344D0DC38AE5ULL;
    D_expected[23] = 0xC3EE4E27532483D8ULL;
    D_expected[24] = 0x0271BFE284B1B424ULL;

    printf("KeccakF1600_StatePermute Benchmark - No Optimizations\n");

    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);
    KeccakF1600_StatePermute(Din);
    cycles = read_csr(mcycle);

    printf("Number of clock cycles for KeccakF1600_StatePermute: %d\n", cycles);

    for (int i = 0; i < 25; i++) {
        if (Din[i] != D_expected[i]) {
            printf("!!! Mismatch at index %d: expected 0x%016llx, got 0x%016llx !!!\n", i, D_expected[i], Din[i]);
            errors++;
        }
    }

    if (errors == 0)    printf("KeccakF1600_StatePermute Benchmark terminated with no errors.\n");
    else                printf("KeccakF1600_StatePermute Benchmark terminated with %d errors\n", errors);
    
	return 0;
}