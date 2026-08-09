/*
 * tests/app-tests/keccak-permute/keccak-permute.c
 *
 * Standalone SW-vs-HW microbenchmark: a single Keccak-f[1600] permutation.
 *
 * SW reference: KeccakF1600_StatePermute(), the standard public-domain
 * reference permutation (same algorithm/round constants as
 * tests/pqc/optimized/falcon512/shake.c's software fallback and the
 * hash-spx sibling test this one mirrors,
 * hash-spx/cva6/tests/keccak-permute/main.c).
 *
 * HW path: this repo's vrf_ip AXI peripheral (vrf_ip/rtl/keccak_f.sv),
 * driven via its legacy raw-permute register interface (DATA_0..DATA_24,
 * CSREG.START/DONE) -- the same CSREG poke/poll pattern
 * tests/pqc/optimized/falcon512/shake.c's process_block_resident() uses
 * to advance a resident SHAKE256 sponge, generalized here to a one-shot
 * write-permute-read of an arbitrary 25-lane state (vrf_axi_top.sv
 * always writes the full post-permutation 1600-bit state back to
 * DATA_0..DATA_24 when CSREG.DONE pulses, so no rate-specific bookkeeping
 * is needed for a raw single permutation).
 */

#include <stdint.h>
#include <string.h>

#include "encoding.h"
#include "vrf_axi.h"
#include "uart.h"

#define VRF_AXI_BASE_ADDR 0x50000000UL

/* ===================================================================== */
/* SW reference: public-domain Keccak-f[1600], extracted from            */
/* hash-spx/cva6/tests/keccak-permute/main.c (same algorithm as          */
/* tests/pqc/optimized/falcon512/shake.c's software path).               */
/* ===================================================================== */

#define NROUNDS 24
#define ROL(a, offset) (((a) << (offset)) ^ ((a) >> (64 - (offset))))

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

static void KeccakF1600_StatePermute(uint64_t *state) {
    int round;

    uint64_t Aba, Abe, Abi, Abo, Abu;
    uint64_t Aga, Age, Agi, Ago, Agu;
    uint64_t Aka, Ake, Aki, Ako, Aku;
    uint64_t Ama, Ame, Ami, Amo, Amu;
    uint64_t Asa, Ase, Asi, Aso, Asu;
    uint64_t BCa, BCe, BCi, BCo, BCu;
    uint64_t Da, De, Di, Do, Du;
    uint64_t Eba, Ebe, Ebi, Ebo, Ebu;
    uint64_t Ega, Ege, Egi, Ego, Egu;
    uint64_t Eka, Eke, Eki, Eko, Eku;
    uint64_t Ema, Eme, Emi, Emo, Emu;
    uint64_t Esa, Ese, Esi, Eso, Esu;

    Aba = state[0];  Abe = state[1];  Abi = state[2];  Abo = state[3];  Abu = state[4];
    Aga = state[5];  Age = state[6];  Agi = state[7];  Ago = state[8];  Agu = state[9];
    Aka = state[10]; Ake = state[11]; Aki = state[12]; Ako = state[13]; Aku = state[14];
    Ama = state[15]; Ame = state[16]; Ami = state[17]; Amo = state[18]; Amu = state[19];
    Asa = state[20]; Ase = state[21]; Asi = state[22]; Aso = state[23]; Asu = state[24];

    for (round = 0; round < NROUNDS; round += 2) {
        BCa = Aba ^ Aga ^ Aka ^ Ama ^ Asa;
        BCe = Abe ^ Age ^ Ake ^ Ame ^ Ase;
        BCi = Abi ^ Agi ^ Aki ^ Ami ^ Asi;
        BCo = Abo ^ Ago ^ Ako ^ Amo ^ Aso;
        BCu = Abu ^ Agu ^ Aku ^ Amu ^ Asu;

        Da = BCu ^ ROL(BCe, 1);
        De = BCa ^ ROL(BCi, 1);
        Di = BCe ^ ROL(BCo, 1);
        Do = BCi ^ ROL(BCu, 1);
        Du = BCo ^ ROL(BCa, 1);

        Aba ^= Da; BCa = Aba;
        Age ^= De; BCe = ROL(Age, 44);
        Aki ^= Di; BCi = ROL(Aki, 43);
        Amo ^= Do; BCo = ROL(Amo, 21);
        Asu ^= Du; BCu = ROL(Asu, 14);
        Eba = BCa ^ ((~BCe) & BCi);
        Eba ^= KeccakF_RoundConstants[round];
        Ebe = BCe ^ ((~BCi) & BCo);
        Ebi = BCi ^ ((~BCo) & BCu);
        Ebo = BCo ^ ((~BCu) & BCa);
        Ebu = BCu ^ ((~BCa) & BCe);

        Abo ^= Do; BCa = ROL(Abo, 28);
        Agu ^= Du; BCe = ROL(Agu, 20);
        Aka ^= Da; BCi = ROL(Aka, 3);
        Ame ^= De; BCo = ROL(Ame, 45);
        Asi ^= Di; BCu = ROL(Asi, 61);
        Ega = BCa ^ ((~BCe) & BCi);
        Ege = BCe ^ ((~BCi) & BCo);
        Egi = BCi ^ ((~BCo) & BCu);
        Ego = BCo ^ ((~BCu) & BCa);
        Egu = BCu ^ ((~BCa) & BCe);

        Abe ^= De; BCa = ROL(Abe, 1);
        Agi ^= Di; BCe = ROL(Agi, 6);
        Ako ^= Do; BCi = ROL(Ako, 25);
        Amu ^= Du; BCo = ROL(Amu, 8);
        Asa ^= Da; BCu = ROL(Asa, 18);
        Eka = BCa ^ ((~BCe) & BCi);
        Eke = BCe ^ ((~BCi) & BCo);
        Eki = BCi ^ ((~BCo) & BCu);
        Eko = BCo ^ ((~BCu) & BCa);
        Eku = BCu ^ ((~BCa) & BCe);

        Abu ^= Du; BCa = ROL(Abu, 27);
        Aga ^= Da; BCe = ROL(Aga, 36);
        Ake ^= De; BCi = ROL(Ake, 10);
        Ami ^= Di; BCo = ROL(Ami, 15);
        Aso ^= Do; BCu = ROL(Aso, 56);
        Ema = BCa ^ ((~BCe) & BCi);
        Eme = BCe ^ ((~BCi) & BCo);
        Emi = BCi ^ ((~BCo) & BCu);
        Emo = BCo ^ ((~BCu) & BCa);
        Emu = BCu ^ ((~BCa) & BCe);

        Abi ^= Di; BCa = ROL(Abi, 62);
        Ago ^= Do; BCe = ROL(Ago, 55);
        Aku ^= Du; BCi = ROL(Aku, 39);
        Ama ^= Da; BCo = ROL(Ama, 41);
        Ase ^= De; BCu = ROL(Ase, 2);
        Esa = BCa ^ ((~BCe) & BCi);
        Ese = BCe ^ ((~BCi) & BCo);
        Esi = BCi ^ ((~BCo) & BCu);
        Eso = BCo ^ ((~BCu) & BCa);
        Esu = BCu ^ ((~BCa) & BCe);

        /* Round 2 (uses E* as input, writes A*) */
        BCa = Eba ^ Ega ^ Eka ^ Ema ^ Esa;
        BCe = Ebe ^ Ege ^ Eke ^ Eme ^ Ese;
        BCi = Ebi ^ Egi ^ Eki ^ Emi ^ Esi;
        BCo = Ebo ^ Ego ^ Eko ^ Emo ^ Eso;
        BCu = Ebu ^ Egu ^ Eku ^ Emu ^ Esu;

        Da = BCu ^ ROL(BCe, 1);
        De = BCa ^ ROL(BCi, 1);
        Di = BCe ^ ROL(BCo, 1);
        Do = BCi ^ ROL(BCu, 1);
        Du = BCo ^ ROL(BCa, 1);

        Eba ^= Da; BCa = Eba;
        Ege ^= De; BCe = ROL(Ege, 44);
        Eki ^= Di; BCi = ROL(Eki, 43);
        Emo ^= Do; BCo = ROL(Emo, 21);
        Esu ^= Du; BCu = ROL(Esu, 14);
        Aba = BCa ^ ((~BCe) & BCi);
        Aba ^= KeccakF_RoundConstants[round + 1];
        Abe = BCe ^ ((~BCi) & BCo);
        Abi = BCi ^ ((~BCo) & BCu);
        Abo = BCo ^ ((~BCu) & BCa);
        Abu = BCu ^ ((~BCa) & BCe);

        Ebo ^= Do; BCa = ROL(Ebo, 28);
        Egu ^= Du; BCe = ROL(Egu, 20);
        Eka ^= Da; BCi = ROL(Eka, 3);
        Eme ^= De; BCo = ROL(Eme, 45);
        Esi ^= Di; BCu = ROL(Esi, 61);
        Aga = BCa ^ ((~BCe) & BCi);
        Age = BCe ^ ((~BCi) & BCo);
        Agi = BCi ^ ((~BCo) & BCu);
        Ago = BCo ^ ((~BCu) & BCa);
        Agu = BCu ^ ((~BCa) & BCe);

        Ebe ^= De; BCa = ROL(Ebe, 1);
        Egi ^= Di; BCe = ROL(Egi, 6);
        Eko ^= Do; BCi = ROL(Eko, 25);
        Emu ^= Du; BCo = ROL(Emu, 8);
        Esa ^= Da; BCu = ROL(Esa, 18);
        Aka = BCa ^ ((~BCe) & BCi);
        Ake = BCe ^ ((~BCi) & BCo);
        Aki = BCi ^ ((~BCo) & BCu);
        Ako = BCo ^ ((~BCu) & BCa);
        Aku = BCu ^ ((~BCa) & BCe);

        Ebu ^= Du; BCa = ROL(Ebu, 27);
        Ega ^= Da; BCe = ROL(Ega, 36);
        Eke ^= De; BCi = ROL(Eke, 10);
        Emi ^= Di; BCo = ROL(Emi, 15);
        Eso ^= Do; BCu = ROL(Eso, 56);
        Ama = BCa ^ ((~BCe) & BCi);
        Ame = BCe ^ ((~BCi) & BCo);
        Ami = BCi ^ ((~BCo) & BCu);
        Amo = BCo ^ ((~BCu) & BCa);
        Amu = BCu ^ ((~BCa) & BCe);

        Ebi ^= Di; BCa = ROL(Ebi, 62);
        Ego ^= Do; BCe = ROL(Ego, 55);
        Eku ^= Du; BCi = ROL(Eku, 39);
        Ema ^= Da; BCo = ROL(Ema, 41);
        Ese ^= De; BCu = ROL(Ese, 2);
        Asa = BCa ^ ((~BCe) & BCi);
        Ase = BCe ^ ((~BCi) & BCo);
        Asi = BCi ^ ((~BCo) & BCu);
        Aso = BCo ^ ((~BCu) & BCa);
        Asu = BCu ^ ((~BCa) & BCe);
    }

    state[0] = Aba;  state[1] = Abe;  state[2] = Abi;  state[3] = Abo;  state[4] = Abu;
    state[5] = Aga;  state[6] = Age;  state[7] = Agi;  state[8] = Ago;  state[9] = Agu;
    state[10] = Aka; state[11] = Ake; state[12] = Aki; state[13] = Ako; state[14] = Aku;
    state[15] = Ama; state[16] = Ame; state[17] = Ami; state[18] = Amo; state[19] = Amu;
    state[20] = Asa; state[21] = Ase; state[22] = Asi; state[23] = Aso; state[24] = Asu;
}

/* ===================================================================== */
/* HW path: vrf_ip's legacy raw-permute register interface.           */
/* ===================================================================== */

static void
keccak_hw_permute(const uint64_t in[25], uint64_t out[25])
{
	uint64_t volatile *data = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_DATA_0_REG_OFFSET);
	uint64_t volatile *csreg = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_CSREG_REG_OFFSET);
	int i;

	for (i = 0; i < 25; i ++) {
		data[i] = in[i];
	}

	__asm__ volatile ("fence" ::: "memory");

	*csreg |= (uint64_t)1 << VRF_CSREG_START_BIT;
	while (((*csreg) & ((uint64_t)1 << VRF_CSREG_DONE_BIT)) == 0);
	/* explicit zero write: genuinely clears START/DONE */
	*csreg = 0;

	for (i = 0; i < 25; i ++) {
		out[i] = data[i];
	}
}

/* ===================================================================== */
/* Test driver                                                           */
/* ===================================================================== */

int
main(void)
{
	static uint64_t in_state[25], sw_state[25], hw_state[25];
	uint32_t cycles_sw, cycles_hw;
	unsigned mismatches, i;

	print_uart("=== keccak-permute: single Keccak-f[1600] permutation ===\n");

	memset(in_state, 0, sizeof in_state);
	in_state[0]  = 0xEC4AFF517369C667ULL; /* SHA3 test pattern */
	in_state[1]  = 0x00000010ABBACD29ULL;
	in_state[15] = 0x8000000000000000ULL;

	memcpy(sw_state, in_state, sizeof in_state);

	clear_csr(mcountinhibit, 1);

	write_csr(mcycle, 0);
	KeccakF1600_StatePermute(sw_state);
	cycles_sw = (uint32_t)read_csr(mcycle);
	print_uart("SW cycles: ");
	print_uart_dec((int)cycles_sw);
	print_uart("\n");

	write_csr(mcycle, 0);
	keccak_hw_permute(in_state, hw_state);
	cycles_hw = (uint32_t)read_csr(mcycle);
	print_uart("HW cycles: ");
	print_uart_dec((int)cycles_hw);
	print_uart("\n");

	mismatches = 0;
	for (i = 0; i < 25; i ++) {
		if (sw_state[i] != hw_state[i]) {
			print_uart("  mismatch[lane ");
			print_uart_dec((int)i);
			print_uart("]: SW=");
			print_uart_int((uint32_t)(sw_state[i] >> 32));
			print_uart_int((uint32_t)sw_state[i]);
			print_uart(" HW=");
			print_uart_int((uint32_t)(hw_state[i] >> 32));
			print_uart_int((uint32_t)hw_state[i]);
			print_uart("\n");
			mismatches ++;
		}
	}

	if (cycles_sw > 0 && cycles_hw > 0) {
		print_uart("Speedup: ");
		print_uart_dec((int)(cycles_sw / cycles_hw));
		print_uart(".");
		{
			uint32_t frac = ((cycles_sw * 100U) / cycles_hw) % 100U;
			if (frac < 10) {
				print_uart("0");
			}
			print_uart_dec((int)frac);
		}
		print_uart("x\n");
	}

	if (mismatches == 0) {
		print_uart("[PASS] HW matches SW element-wise (25 lanes)\n");
		return 0;
	}

	print_uart("[FAIL] ");
	print_uart_dec((int)mismatches);
	print_uart(" / 25 lanes mismatched\n");
	return 1;
}
