#include <stdio.h>
#include <inttypes.h>
#include <string.h>

#include "./inc/uart.h"
#include "encoding.h"

#define SIZE 50


#define NROUNDS 24
// #define ROL(a, offset) (((a) << (offset)) ^ ((a) >> (64 - (offset))))
#define ROL(x, n) (((x) << (n)) | ((x) >> ((64 - (n)) & 63)))

// BCe = Age ^ (BCa ^ ROL(BCi, 1)) rotated by 44 bits (KTOPH?)
//#define DXROL3(a, b, c, shamt) ROL(a ^ (b ^ ROL(c, 1)), shamt)

#define DXROL3(dest, a, b, c, shamt) \
    asm volatile ( \
        ".insn r4 MADD, 0x2, 0x02, %[rd], %[r1], %[r2], %[r3]\n" \
        "rol %[rd], %[rd], %[rs]" \
        : [rd] "=&r" (dest) \
        : [r1] "r" (a), [r2] "r" (b), [r3] "r" (c), [rs] "r" (shamt) \
    )

#define XOR5(dest, a, b, c, d, e) \
    asm volatile ( \
        ".insn r4 MADD, 0x0, 0x02, %[rd], %[r1], %[r2], %[r3]\n" \
        ".insn r4 MADD, 0x0, 0x02, %[rd], %[rd], %[r4], %[r5]" \
        : [rd] "=&r" (dest) \
        : [r1] "r" (a), [r2] "r" (b), [r3] "r" (c), [r4] "r" (d), [r5] "r" (e) \
    );

#define KCOP(dest, a, b, c) \
    asm volatile ( \
        ".insn r4 MADD, 0x01, 0x02, %[rd], %[r1], %[r2], %[r3]\n" \
        : [rd] "=&r" (dest) \
        : [r1] "r" (a), [r2] "r" (b), [r3] "r" (c) \
    );

#define KTOP(dest, a, b) \
    asm volatile ( \
        ".insn r CUSTOM_0, 0x00, 0x00, %[rd], %[r1], %[r2] \n" \
        : [rd] "=&r" (dest) \
        : [r1] "r" (a), [r2] "r" (b) \
    );


/* Keccak round constants */
static const uint64_t KeccakF_RoundConstants[NROUNDS] = {
    0x0000000000000001ULL, 0x0000000000008082ULL,
    0x800000000000808aULL, 0x8000000080008000ULL,
    0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL,
    0x000000000000008aULL, 0x0000000000000088ULL,
    0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL,
    0x8000000000008089ULL, 0x8000000000008003ULL,
    0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL,
    0x8000000080008081ULL, 0x8000000000008080ULL,
    0x0000000080000001ULL, 0x8000000080008008ULL
};

/*************************************************
 * Name:        KeccakF1600_StatePermute
 *
 * Description: The Keccak F1600 Permutation
 *
 * Arguments:   - uint64_t *state: pointer to input/output Keccak state
 **************************************************/
static void KeccakF1600_StatePermute(uint64_t *state) {
    int round;

    uint64_t Aba, Abe, Abi, Abo, Abu;
    uint64_t Aga, Age, Agi, Ago, Agu;
    uint64_t Aka, Ake, Aki, Ako, Aku;
    uint64_t Ama, Ame, Ami, Amo, Amu;
    uint64_t Asa, Ase, Asi, Aso, Asu;
    uint64_t BCa, BCe, BCi, BCo, BCu;
    uint64_t BCan, BCen, BCin, BCon, BCun;
    uint64_t Eba, Ebe, Ebi, Ebo, Ebu;
    uint64_t Ega, Ege, Egi, Ego, Egu;
    uint64_t Eka, Eke, Eki, Eko, Eku;
    uint64_t Ema, Eme, Emi, Emo, Emu;
    uint64_t Esa, Ese, Esi, Eso, Esu;

    // copyFromState(A, state)
    Aba = state[0];
    Abe = state[1];
    Abi = state[2];
    Abo = state[3];
    Abu = state[4];
    Aga = state[5];
    Age = state[6];
    Agi = state[7];
    Ago = state[8];
    Agu = state[9];
    Aka = state[10];
    Ake = state[11];
    Aki = state[12];
    Ako = state[13];
    Aku = state[14];
    Ama = state[15];
    Ame = state[16];
    Ami = state[17];
    Amo = state[18];
    Amu = state[19];
    Asa = state[20];
    Ase = state[21];
    Asi = state[22];
    Aso = state[23];
    Asu = state[24];

    for (round = 0; round < NROUNDS; round += 2) {
        //    prepareTheta
       XOR5(BCa, Aba, Aga, Aka, Ama, Asa);
       XOR5(BCe, Abe, Age, Ake, Ame, Ase);
       XOR5(BCi, Abi, Agi, Aki, Ami, Asi);
       XOR5(BCo, Abo, Ago, Ako, Amo, Aso);
       XOR5(BCu, Abu, Agu, Aku, Amu, Asu);

        // thetaRhoPiChiIotaPrepareTheta(round  , A, E)
        DXROL3(BCan, Aba, BCu, BCe, 0);
        DXROL3(BCen, Age, BCa, BCi, 44);
        DXROL3(BCin, Aki, BCe, BCo, 43);
        DXROL3(BCon, Amo, BCi, BCu, 21);
        DXROL3(BCun, Asu, BCo, BCa, 14);

        KCOP(Eba, BCan, BCen, BCin);
        Eba ^= KeccakF_RoundConstants[round];
        KCOP(Ebe, BCen, BCin, BCon);
        KCOP(Ebi, BCin, BCon, BCun);
        KCOP(Ebo, BCon, BCun, BCan);
        KCOP(Ebu, BCun, BCan, BCen);

        DXROL3(BCan, Abo, BCi, BCu, 28);
        DXROL3(BCen, Agu, BCo, BCa, 20);
        DXROL3(BCin, Aka, BCu, BCe, 3);
        DXROL3(BCon, Ame, BCa, BCi, 45);
        DXROL3(BCun, Asi, BCe, BCo, 61);

        KCOP(Ega, BCan, BCen, BCin);
        KCOP(Ege, BCen, BCin, BCon);
        KCOP(Egi, BCin, BCon, BCun);
        KCOP(Ego, BCon, BCun, BCan);
        KCOP(Egu, BCun, BCan, BCen);

        DXROL3(BCan, Abe, BCa, BCi, 1);
        DXROL3(BCen, Agi, BCe, BCo, 6);
        DXROL3(BCin, Ako, BCi, BCu, 25);
        DXROL3(BCon, Amu, BCo, BCa, 8);
        DXROL3(BCun, Asa, BCu, BCe, 18);

        KCOP(Eka, BCan, BCen, BCin);
        KCOP(Eke, BCen, BCin, BCon);
        KCOP(Eki, BCin, BCon, BCun);
        KCOP(Eko, BCon, BCun, BCan);
        KCOP(Eku, BCun, BCan, BCen);

        DXROL3(BCan, Abu, BCo, BCa, 27);
        DXROL3(BCen, Aga, BCu, BCe, 36);
        DXROL3(BCin, Ake, BCa, BCi, 10);
        DXROL3(BCon, Ami, BCe, BCo, 15);
        DXROL3(BCun, Aso, BCi, BCu, 56);

        KCOP(Ema, BCan, BCen, BCin);
        KCOP(Eme, BCen, BCin, BCon);
        KCOP(Emi, BCin, BCon, BCun);
        KCOP(Emo, BCon, BCun, BCan);
        KCOP(Emu, BCun, BCan, BCen);

        DXROL3(BCan, Abi, BCe, BCo, 62);
        DXROL3(BCen, Ago, BCi, BCu, 55);
        DXROL3(BCin, Aku, BCo, BCa, 39);
        DXROL3(BCon, Ama, BCu, BCe, 41);
        DXROL3(BCun, Ase, BCa, BCi, 2);

        KCOP(Esa, BCan, BCen, BCin);
        KCOP(Ese, BCen, BCin, BCon);
        KCOP(Esi, BCin, BCon, BCun);
        KCOP(Eso, BCon, BCun, BCan);
        KCOP(Esu, BCun, BCan, BCen);

        //    prepareTheta
        XOR5(BCa, Eba, Ega, Eka, Ema, Esa);
        XOR5(BCe, Ebe, Ege, Eke, Eme, Ese);
        XOR5(BCi, Ebi, Egi, Eki, Emi, Esi);
        XOR5(BCo, Ebo, Ego, Eko, Emo, Eso);
        XOR5(BCu, Ebu, Egu, Eku, Emu, Esu);

        // thetaRhoPiChiIotaPrepareTheta(round+1, E, A)
        DXROL3(BCan, Eba, BCu, BCe, 0);
        DXROL3(BCen, Ege, BCa, BCi, 44);
        DXROL3(BCin, Eki, BCe, BCo, 43);
        DXROL3(BCon, Emo, BCi, BCu, 21);
        DXROL3(BCun, Esu, BCo, BCa, 14);

        KCOP(Aba, BCan, BCen, BCin);
        Aba ^= KeccakF_RoundConstants[round + 1];
        KCOP(Abe, BCen, BCin, BCon);
        KCOP(Abi, BCin, BCon, BCun);
        KCOP(Abo, BCon, BCun, BCan);
        KCOP(Abu, BCun, BCan, BCen);
       
        DXROL3(BCan, Ebo, BCi, BCu, 28);
        DXROL3(BCen, Egu, BCo, BCa, 20);
        DXROL3(BCin, Eka, BCu, BCe, 3);
        DXROL3(BCon, Eme, BCa, BCi, 45);
        DXROL3(BCun, Esi, BCe, BCo, 61);

        KCOP(Aga, BCan, BCen, BCin);
        KCOP(Age, BCen, BCin, BCon);
        KCOP(Agi, BCin, BCon, BCun);
        KCOP(Ago, BCon, BCun, BCan);
        KCOP(Agu, BCun, BCan, BCen);

        DXROL3(BCan, Ebe, BCa, BCi, 1);
        DXROL3(BCen, Egi, BCe, BCo, 6);
        DXROL3(BCin, Eko, BCi, BCu, 25);
        DXROL3(BCon, Emu, BCo, BCa, 8);
        DXROL3(BCun, Esa, BCu, BCe, 18);

        KCOP(Aka, BCan, BCen, BCin);
        KCOP(Ake, BCen, BCin, BCon);
        KCOP(Aki, BCin, BCon, BCun);
        KCOP(Ako, BCon, BCun, BCan);
        KCOP(Aku, BCun, BCan, BCen);

        DXROL3(BCan, Ebu, BCo, BCa, 27);
        DXROL3(BCen, Ega, BCu, BCe, 36);
        DXROL3(BCin, Eke, BCa, BCi, 10);
        DXROL3(BCon, Emi, BCe, BCo, 15);
        DXROL3(BCun, Eso, BCi, BCu, 56);

        KCOP(Ama, BCan, BCen, BCin);
        KCOP(Ame, BCen, BCin, BCon);
        KCOP(Ami, BCin, BCon, BCun);
        KCOP(Amo, BCon, BCun, BCan);
        KCOP(Amu, BCun, BCan, BCen);

        DXROL3(BCan, Ebi, BCe, BCo, 62);
        DXROL3(BCen, Ego, BCi, BCu, 55);
        DXROL3(BCin, Eku, BCo, BCa, 39);
        DXROL3(BCon, Ema, BCu, BCe, 41);
        DXROL3(BCun, Ese, BCa, BCi, 2);

        KCOP(Asa, BCan, BCen, BCin);
        KCOP(Ase, BCen, BCin, BCon);
        KCOP(Asi, BCin, BCon, BCun);
        KCOP(Aso, BCon, BCun, BCan);
        KCOP(Asu, BCun, BCan, BCen);
    }

    // copyToState(state, A)
    state[0] = Aba;
    state[1] = Abe;
    state[2] = Abi;
    state[3] = Abo;
    state[4] = Abu;
    state[5] = Aga;
    state[6] = Age;
    state[7] = Agi;
    state[8] = Ago;
    state[9] = Agu;
    state[10] = Aka;
    state[11] = Ake;
    state[12] = Aki;
    state[13] = Ako;
    state[14] = Aku;
    state[15] = Ama;
    state[16] = Ame;
    state[17] = Ami;
    state[18] = Amo;
    state[19] = Amu;
    state[20] = Asa;
    state[21] = Ase;
    state[22] = Asi;
    state[23] = Aso;
    state[24] = Asu;
}


int main(){
	static uint32_t Din[SIZE] __attribute__ ((aligned (4)));
	static uint32_t Dout[SIZE] __attribute__ ((aligned (4)));

	static uint32_t D_expected[SIZE];
	int i = 0;

	memset(Din, 0, sizeof(Din));
	memset(Dout, 0, sizeof(Dout));
	memset(D_expected, 0, sizeof(D_expected));

	unsigned int cycles;
 
	Din[0] = 0x7369C667;
	Din[1] = 0xEC4AFF51;
	Din[2] = 0xABBACD29;
	Din[3] = 0x00000010;
	Din[31] = 0x80000000;

	D_expected[1] = 0xE1ADB0E2;
	D_expected[0] = 0xE7CB8356;
	D_expected[3] = 0xBB3F5FB8;
	D_expected[2] = 0x573A5BD7;
	D_expected[5] = 0xF7CA02A1;
	D_expected[4] = 0xE9784CC5;
	D_expected[7] = 0x6E54F256;
	D_expected[6] = 0x60A4C685;
	D_expected[9] = 0x77051F83;
	D_expected[8] = 0x243FCBAA;
	D_expected[11] = 0x6459DB0B;
	D_expected[10] = 0x4C063DD5;
	D_expected[13] = 0xE046DE71;
	D_expected[12] = 0xCB4B81C6;
	D_expected[15] = 0x94051793;
	D_expected[14] = 0xDB31F24C;
	D_expected[17] = 0xA13FC86C;
	D_expected[16] = 0xF16E32DD;
	D_expected[19] = 0xB962FC91;
	D_expected[18] = 0xB7737708;
	D_expected[21] = 0xD3CA2E7A;
	D_expected[20] = 0xFA27C801;
	D_expected[23] = 0x53C85108;
	D_expected[22] = 0xF72A3CCA;
	D_expected[25] = 0x73E732CD;
	D_expected[24] = 0xADF0E783;
	D_expected[27] = 0x8470BD54;
	D_expected[26] = 0xC4BDD1BF; 
	D_expected[29] = 0xD10B916F;
	D_expected[28] = 0x7C8C1F77; 
	D_expected[31] = 0x51129474;
	D_expected[30] = 0x440A2670; 
	D_expected[33] = 0x3D77CB49;
	D_expected[32] = 0xE9960C44; 
	D_expected[35] = 0xEC5001EB;
	D_expected[34] = 0xE4251E39; 
	D_expected[37] = 0x77A0EEC5;
	D_expected[36] = 0xEA4FD653;
	D_expected[39] = 0xEBC86BD4;
	D_expected[38] = 0x7B6773E7; 
	D_expected[41] = 0xE77DF6B0;
	D_expected[40] = 0x128FDC4B; 
	D_expected[43] = 0x0DB0D48A;
	D_expected[42] = 0x02F1B12E; 
	D_expected[45] = 0x241B344D;
	D_expected[44] = 0x0DC38AE5;
	D_expected[47] = 0xC3EE4E27;
	D_expected[46] = 0x532483D8;
	D_expected[49] = 0x0271BFE2;
	D_expected[48] = 0x84B1B424;
	print_uart("Hello Keccak\n");

    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);
	KeccakF1600_StatePermute(Din);	
    cycles = read_csr(mcycle);

	print_uart("Number of clock cycles for KeccakF1600_StatePermute: ");
	print_uart_dec(cycles);
	print_uart("\n");

	for (i = 0; i< SIZE; i++ ){
		if (Din[i] != D_expected[i]){
			print_uart("ERROR keccak output did not match test vector. ");
			print_uart("Expected D[");
			print_uart_dec(i);
			print_uart("]: ");
			print_uart_addr(D_expected[i]);
			print_uart(" but obtained ");
			print_uart_addr(Din[i]);
			print_uart("\n");
		}	
	}	

    print_uart("Keccak terminated!\n");
	return 0;
}