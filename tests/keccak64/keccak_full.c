// Keccak Accellerator IP - Tightly
// C Benchmark for the State Permutation Function - Full coprocessor Implementation 
// Author: Federico Runco

#include "inc/uart.h"
#include "encoding.h"
#include "inc/keccak_copro.h"

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

    register uint64_t s00, s01, s02, s03, s04;
    register uint64_t s05, s06, s07, s08, s09;
    register uint64_t s10, s11, s12, s13, s14;
    register uint64_t s15, s16, s17, s18, s19;
    register uint64_t s20, s21, s22, s23, s24;

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
        uint64_t C0, C1, C2, C3, C4, C5;

        XOR5(C0, s00, s05, s10, s15, s20);
        XOR5(C1, s01, s06, s11, s16, s21);
        XOR5(C2, s02, s07, s12, s17, s22);
        XOR5(C3, s04, s09, s14, s19, s24);
        XOR5(C4, s03, s08, s13, s18, s23);

        C5 = s05;
        DXROL3(s05, s03, C2, C3, 28);
        DXROL3(s03, s18, C2, C3, 21);
        DXROL3(s18, s17, C1, C4, 15);
        DXROL3(s17, s11, C0, C2, 10);
        DXROL3(s11, s07, C1, C4, 6);
        DXROL3(s07, s10, C3, C1, 3);
        DXROL3(s10, s01, C0, C2, 1);
        DXROL3(s01, s06, C0, C2, 44);
        DXROL3(s06, s09, C4, C0, 20);
        DXROL3(s09, s22, C1, C4, 61);
        DXROL3(s22, s14, C4, C0, 39);
        DXROL3(s14, s20, C3, C1, 18);
        DXROL3(s20, s02, C1, C4, 62);
        DXROL3(s02, s12, C1, C4, 43);
        DXROL3(s12, s13, C2, C3, 25);
        DXROL3(s13, s19, C4, C0, 8);
        DXROL3(s19, s23, C2, C3, 56);
        DXROL3(s23, s15, C3, C1, 41);
        DXROL3(s15, s04, C4, C0, 27);
        DXROL3(s04, s24, C4, C0, 14);
        DXROL3(s24, s21, C0, C2, 2);
        DXROL3(s21, s08, C2, C3, 55);
        DXROL3(s08, s16, C0, C2, 45);
        DXROL3(s16, C5, C3, C1, 36);
        DXROL3(s00, s00, C3, C1, 0);

        C0 = s04;
        XANDN(s04, s04, s00, s01);
        XANDN(s01, s01, s02, s03);
        XANDN(s03, s03, s04, s00);
        XANDN(s00, s00, s01, s02);
        XANDN(s02, s02, s03, C0);

        C0 = s09;
        XANDN(s09, s09, s05, s06);
        XANDN(s06, s06, s07, s08);
        XANDN(s08, s08, s09, s05);
        XANDN(s05, s05, s06, s07);
        XANDN(s07, s07, s08, C0);

        C0 = s14;
        XANDN(s14, s14, s10, s11);
        XANDN(s11, s11, s12, s13);
        XANDN(s13, s13, s14, s10);
        XANDN(s10, s10, s11, s12);
        XANDN(s12, s12, s13, C0);

        C0 = s19;
        XANDN(s19, s19, s15, s16);
        XANDN(s16, s16, s17, s18);
        XANDN(s18, s18, s19, s15);
        XANDN(s15, s15, s16, s17);
        XANDN(s17, s17, s18, C0);

        C0 = s24;
        XANDN(s24, s24, s20, s21);
        XANDN(s21, s21, s22, s23);
        XANDN(s23, s23, s24, s20);
        XANDN(s20, s20, s21, s22);
        XANDN(s22, s22, s23, C0);
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

    printf("KeccakF1600_StatePermute Benchmark - Coprocessor\n");

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