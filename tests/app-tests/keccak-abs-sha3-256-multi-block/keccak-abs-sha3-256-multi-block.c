/*
 * tests/app-tests/keccak-abs-sha3-256-multi-block/keccak-abs-sha3-256-multi-block.c
 *
 * Standalone SW-vs-HW microbenchmark: non-incremental SHA3-256
 * (absorb-once + squeeze), a 200-byte message spanning two 136-byte rate
 * blocks, mirroring
 * hash-spx/cva6/tests/keccak-abs-sha3-256-multi-block/main.c's
 * SW-reference logic and test vector, but with the hardware call
 * replaced by digsig's vrf_ip AXI peripheral (base 0x5000_0000,
 * vrf_ip/sw/vrf_axi.h) instead of hash-spx's own CVXIF coprocessor.
 *
 * SW reference: fips202.c's keccak_absorb_once()/keccak_squeeze()/
 * KeccakF1600_StatePermute(), extracted from
 * hash-spx/cva6/tests/keccak-abs-sha3-256-multi-block/fips202.c
 * (public-domain Keccak reference), trimmed to the non-incremental
 * sha3_256() entry point this test exercises.
 *
 * HW path: vrf_ip's job-based DMA absorb engine
 * (vrf_ip/rtl/keccak_dma_ctrl.sv, JOB_SRC_ADDR/JOB_SRC_LEN/JOBCTRL.GO,
 * the same call sequence tests/pqc/optimized/falcon512/shake.c drives).
 * A 200-byte message pads out to 272 bytes (two 136-byte rate blocks);
 * keccak_dma_ctrl.sv's byte-wise absorb engine chains the permutation
 * across both block boundaries autonomously within a single DMA job (no
 * CPU round trip in between) -- this is the actual multi-block exercise
 * this test is named for. The pad10*1 padding (message || 0x06 ||
 * 0x00...0x00 || final byte |= 0x80) is built in software and absorbed
 * as plain data instead of using JOBCTRL.FLIP: the DMA engine hardwires
 * FLIP's domain byte to 0x1F (see keccak_dma_ctrl.sv's FLIP_BYTE0
 * state), correct for SHAKE256 (see the sibling keccak-abs-shake256
 * test) but wrong for SHA3-256's 0x06 domain separator.
 */

#include <stdint.h>
#include <string.h>

#include "encoding.h"
#include "vrf_axi.h"
#include "uart.h"

#define VRF_AXI_BASE_ADDR 0x50000000UL

/* ===================================================================== */
/* SW reference: public-domain Keccak-f[1600] + SHAKE256 sponge,         */
/* extracted from hash-spx/cva6/tests/keccak-abs-shake256/fips202.c.     */
/* ===================================================================== */

#define NROUNDS 24
#define ROL(a, offset) ((a << offset) ^ (a >> (64-offset)))

static const uint64_t KeccakF_RoundConstants[NROUNDS] = {
  (uint64_t)0x0000000000000001ULL, (uint64_t)0x0000000000008082ULL,
  (uint64_t)0x800000000000808aULL, (uint64_t)0x8000000080008000ULL,
  (uint64_t)0x000000000000808bULL, (uint64_t)0x0000000080000001ULL,
  (uint64_t)0x8000000080008081ULL, (uint64_t)0x8000000000008009ULL,
  (uint64_t)0x000000000000008aULL, (uint64_t)0x0000000000000088ULL,
  (uint64_t)0x0000000080008009ULL, (uint64_t)0x000000008000000aULL,
  (uint64_t)0x000000008000808bULL, (uint64_t)0x800000000000008bULL,
  (uint64_t)0x8000000000008089ULL, (uint64_t)0x8000000000008003ULL,
  (uint64_t)0x8000000000008002ULL, (uint64_t)0x8000000000000080ULL,
  (uint64_t)0x000000000000800aULL, (uint64_t)0x800000008000000aULL,
  (uint64_t)0x8000000080008081ULL, (uint64_t)0x8000000000008080ULL,
  (uint64_t)0x0000000080000001ULL, (uint64_t)0x8000000080008008ULL
};

static void KeccakF1600_StatePermute(uint64_t state[25])
{
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

        Aba = state[ 0]; Abe = state[ 1]; Abi = state[ 2]; Abo = state[ 3]; Abu = state[ 4];
        Aga = state[ 5]; Age = state[ 6]; Agi = state[ 7]; Ago = state[ 8]; Agu = state[ 9];
        Aka = state[10]; Ake = state[11]; Aki = state[12]; Ako = state[13]; Aku = state[14];
        Ama = state[15]; Ame = state[16]; Ami = state[17]; Amo = state[18]; Amu = state[19];
        Asa = state[20]; Ase = state[21]; Asi = state[22]; Aso = state[23]; Asu = state[24];

        for(round = 0; round < NROUNDS; round += 2) {
            BCa = Aba^Aga^Aka^Ama^Asa;
            BCe = Abe^Age^Ake^Ame^Ase;
            BCi = Abi^Agi^Aki^Ami^Asi;
            BCo = Abo^Ago^Ako^Amo^Aso;
            BCu = Abu^Agu^Aku^Amu^Asu;

            Da = BCu^ROL(BCe, 1); De = BCa^ROL(BCi, 1); Di = BCe^ROL(BCo, 1);
            Do = BCi^ROL(BCu, 1); Du = BCo^ROL(BCa, 1);

            Aba ^= Da; BCa = Aba;
            Age ^= De; BCe = ROL(Age, 44);
            Aki ^= Di; BCi = ROL(Aki, 43);
            Amo ^= Do; BCo = ROL(Amo, 21);
            Asu ^= Du; BCu = ROL(Asu, 14);
            Eba =   BCa ^((~BCe)&  BCi ); Eba ^= (uint64_t)KeccakF_RoundConstants[round];
            Ebe =   BCe ^((~BCi)&  BCo ); Ebi =   BCi ^((~BCo)&  BCu );
            Ebo =   BCo ^((~BCu)&  BCa ); Ebu =   BCu ^((~BCa)&  BCe );

            Abo ^= Do; BCa = ROL(Abo, 28);
            Agu ^= Du; BCe = ROL(Agu, 20);
            Aka ^= Da; BCi = ROL(Aka,  3);
            Ame ^= De; BCo = ROL(Ame, 45);
            Asi ^= Di; BCu = ROL(Asi, 61);
            Ega =   BCa ^((~BCe)&  BCi ); Ege =   BCe ^((~BCi)&  BCo );
            Egi =   BCi ^((~BCo)&  BCu ); Ego =   BCo ^((~BCu)&  BCa ); Egu =   BCu ^((~BCa)&  BCe );

            Abe ^= De; BCa = ROL(Abe,  1);
            Agi ^= Di; BCe = ROL(Agi,  6);
            Ako ^= Do; BCi = ROL(Ako, 25);
            Amu ^= Du; BCo = ROL(Amu,  8);
            Asa ^= Da; BCu = ROL(Asa, 18);
            Eka =   BCa ^((~BCe)&  BCi ); Eke =   BCe ^((~BCi)&  BCo );
            Eki =   BCi ^((~BCo)&  BCu ); Eko =   BCo ^((~BCu)&  BCa ); Eku =   BCu ^((~BCa)&  BCe );

            Abu ^= Du; BCa = ROL(Abu, 27);
            Aga ^= Da; BCe = ROL(Aga, 36);
            Ake ^= De; BCi = ROL(Ake, 10);
            Ami ^= Di; BCo = ROL(Ami, 15);
            Aso ^= Do; BCu = ROL(Aso, 56);
            Ema =   BCa ^((~BCe)&  BCi ); Eme =   BCe ^((~BCi)&  BCo );
            Emi =   BCi ^((~BCo)&  BCu ); Emo =   BCo ^((~BCu)&  BCa ); Emu =   BCu ^((~BCa)&  BCe );

            Abi ^= Di; BCa = ROL(Abi, 62);
            Ago ^= Do; BCe = ROL(Ago, 55);
            Aku ^= Du; BCi = ROL(Aku, 39);
            Ama ^= Da; BCo = ROL(Ama, 41);
            Ase ^= De; BCu = ROL(Ase,  2);
            Esa =   BCa ^((~BCe)&  BCi ); Ese =   BCe ^((~BCi)&  BCo );
            Esi =   BCi ^((~BCo)&  BCu ); Eso =   BCo ^((~BCu)&  BCa ); Esu =   BCu ^((~BCa)&  BCe );

            BCa = Eba^Ega^Eka^Ema^Esa;
            BCe = Ebe^Ege^Eke^Eme^Ese;
            BCi = Ebi^Egi^Eki^Emi^Esi;
            BCo = Ebo^Ego^Eko^Emo^Eso;
            BCu = Ebu^Egu^Eku^Emu^Esu;

            Da = BCu^ROL(BCe, 1); De = BCa^ROL(BCi, 1); Di = BCe^ROL(BCo, 1);
            Do = BCi^ROL(BCu, 1); Du = BCo^ROL(BCa, 1);

            Eba ^= Da; BCa = Eba;
            Ege ^= De; BCe = ROL(Ege, 44);
            Eki ^= Di; BCi = ROL(Eki, 43);
            Emo ^= Do; BCo = ROL(Emo, 21);
            Esu ^= Du; BCu = ROL(Esu, 14);
            Aba =   BCa ^((~BCe)&  BCi ); Aba ^= (uint64_t)KeccakF_RoundConstants[round+1];
            Abe =   BCe ^((~BCi)&  BCo ); Abi =   BCi ^((~BCo)&  BCu );
            Abo =   BCo ^((~BCu)&  BCa ); Abu =   BCu ^((~BCa)&  BCe );

            Ebo ^= Do; BCa = ROL(Ebo, 28);
            Egu ^= Du; BCe = ROL(Egu, 20);
            Eka ^= Da; BCi = ROL(Eka, 3);
            Eme ^= De; BCo = ROL(Eme, 45);
            Esi ^= Di; BCu = ROL(Esi, 61);
            Aga =   BCa ^((~BCe)&  BCi ); Age =   BCe ^((~BCi)&  BCo );
            Agi =   BCi ^((~BCo)&  BCu ); Ago =   BCo ^((~BCu)&  BCa ); Agu =   BCu ^((~BCa)&  BCe );

            Ebe ^= De; BCa = ROL(Ebe, 1);
            Egi ^= Di; BCe = ROL(Egi, 6);
            Eko ^= Do; BCi = ROL(Eko, 25);
            Emu ^= Du; BCo = ROL(Emu, 8);
            Esa ^= Da; BCu = ROL(Esa, 18);
            Aka =   BCa ^((~BCe)&  BCi ); Ake =   BCe ^((~BCi)&  BCo );
            Aki =   BCi ^((~BCo)&  BCu ); Ako =   BCo ^((~BCu)&  BCa ); Aku =   BCu ^((~BCa)&  BCe );

            Ebu ^= Du; BCa = ROL(Ebu, 27);
            Ega ^= Da; BCe = ROL(Ega, 36);
            Eke ^= De; BCi = ROL(Eke, 10);
            Emi ^= Di; BCo = ROL(Emi, 15);
            Eso ^= Do; BCu = ROL(Eso, 56);
            Ama =   BCa ^((~BCe)&  BCi ); Ame =   BCe ^((~BCi)&  BCo );
            Ami =   BCi ^((~BCo)&  BCu ); Amo =   BCo ^((~BCu)&  BCa ); Amu =   BCu ^((~BCa)&  BCe );

            Ebi ^= Di; BCa = ROL(Ebi, 62);
            Ego ^= Do; BCe = ROL(Ego, 55);
            Eku ^= Du; BCi = ROL(Eku, 39);
            Ema ^= Da; BCo = ROL(Ema, 41);
            Ese ^= De; BCu = ROL(Ese, 2);
            Asa =   BCa ^((~BCe)&  BCi ); Ase =   BCe ^((~BCi)&  BCo );
            Asi =   BCi ^((~BCo)&  BCu ); Aso =   BCo ^((~BCu)&  BCa ); Asu =   BCu ^((~BCa)&  BCe );
        }

        state[ 0] = Aba; state[ 1] = Abe; state[ 2] = Abi; state[ 3] = Abo; state[ 4] = Abu;
        state[ 5] = Aga; state[ 6] = Age; state[ 7] = Agi; state[ 8] = Ago; state[ 9] = Agu;
        state[10] = Aka; state[11] = Ake; state[12] = Aki; state[13] = Ako; state[14] = Aku;
        state[15] = Ama; state[16] = Ame; state[17] = Ami; state[18] = Amo; state[19] = Amu;
        state[20] = Asa; state[21] = Ase; state[22] = Asi; state[23] = Aso; state[24] = Asu;
}

#define SHA3_256_RATE 136

static void keccak_absorb_once(uint64_t s[25], unsigned int r,
    const uint8_t *in, size_t inlen, uint8_t p)
{
  unsigned int i;

  for(i=0;i<25;i++)
    s[i] = 0;

  while(inlen >= r) {
    for(i=0;i<r/8;i++) {
      uint64_t w = 0;
      unsigned int b;
      for (b = 0; b < 8; b++) w |= (uint64_t)in[8*i+b] << (8*b);
      s[i] ^= w;
    }
    in += r;
    inlen -= r;
    KeccakF1600_StatePermute(s);
  }

  for(i=0;i<inlen;i++)
    s[i/8] ^= (uint64_t)in[i] << 8*(i%8);

  s[i/8] ^= (uint64_t)p << 8*(i%8);
  s[(r-1)/8] ^= 1ULL << 63;
}

static unsigned int keccak_squeeze(uint8_t *out, size_t outlen,
    uint64_t s[25], unsigned int pos, unsigned int r)
{
  unsigned int i;

  while(outlen) {
    if(pos == r) {
      KeccakF1600_StatePermute(s);
      pos = 0;
    }
    for(i=pos;i < r && i < pos+outlen; i++)
      *out++ = (uint8_t)(s[i/8] >> 8*(i%8));
    outlen -= i-pos;
    pos = i;
  }

  return pos;
}

static void sha3_256(uint8_t h[32], const uint8_t *in, size_t inlen)
{
  uint64_t s[25];

  keccak_absorb_once(s, SHA3_256_RATE, in, inlen, 0x06);
  KeccakF1600_StatePermute(s);
  /* state is already permuted above -- pos=0 (not r) avoids
   * keccak_squeeze() triggering a second, spurious permutation. */
  keccak_squeeze(h, 32, s, 0, SHA3_256_RATE);
}

/* ===================================================================== */
/* HW path: vrf_ip's job-based DMA absorb engine + legacy CSREG       */
/* raw-permute squeeze, extracted/adapted from                          */
/* tests/pqc/optimized/falcon512/shake.c's call sequence.                */
/* ===================================================================== */

#define VRF_HW_RATE 136   /* the only rate keccak_dma_ctrl.sv targets */
#define VRF_HW_PADDED_MAX 272   /* 200-byte message -> 2 x 136-byte rate blocks */

static void
keccak_hw_absorb_job(const void *in, uint32_t len, int fresh)
{
	uint64_t volatile *job_src_addr = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_JOB_SRC_ADDR_REG_OFFSET);
	uint64_t volatile *job_src_len = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_JOB_SRC_LEN_REG_OFFSET);
	uint64_t volatile *jobctrl = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_JOBCTRL_REG_OFFSET);
	uint64_t ctrl;

	__asm__ volatile ("fence" ::: "memory");

	*job_src_addr = (uint64_t)(uintptr_t)in;
	*job_src_len  = len;

	ctrl = (uint64_t)1 << VRF_JOBCTRL_GO_BIT;
	if (fresh) {
		ctrl |= (uint64_t)1 << VRF_JOBCTRL_FRESH_BIT;
	}
	*jobctrl = ctrl;
	while (((*jobctrl) & ((uint64_t)1 << VRF_JOBCTRL_DONE_BIT)) == 0);
	*jobctrl = 0;
}

static void
keccak_hw_permute_pulse(void)
{
	uint64_t volatile *csreg = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_CSREG_REG_OFFSET);

	*csreg |= (uint64_t)1 << VRF_CSREG_START_BIT;
	while (((*csreg) & ((uint64_t)1 << VRF_CSREG_DONE_BIT)) == 0);
	*csreg = 0;
}

static void
keccak_hw_squeeze_bytes(uint8_t *dst, size_t n)
{
	uint64_t volatile *data = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_DATA_0_REG_OFFSET);
	size_t i;

	for (i = 0; i < n; i ++) {
		dst[i] = (uint8_t)(data[i >> 3] >> ((i & 7) << 3));
	}
}

/*
 * Non-incremental HW hash: absorb pad10*1(in||dsep) via a single DMA
 * job, then squeeze outlen bytes, permuting between rate blocks via the
 * legacy CSREG raw-permute path.
 */
static void
keccak_hw_hash(const uint8_t *in, size_t inlen, uint8_t dsep,
    uint8_t *out, size_t outlen)
{
	uint8_t padded[VRF_HW_PADDED_MAX];
	size_t nblocks, padded_len;

	nblocks = inlen / VRF_HW_RATE + 1;
	padded_len = nblocks * VRF_HW_RATE;
	memset(padded, 0, padded_len);
	memcpy(padded, in, inlen);
	padded[inlen] ^= dsep;
	padded[padded_len - 1] ^= 0x80;

	keccak_hw_absorb_job(padded, (uint32_t)padded_len, 1);

	while (outlen > 0) {
		size_t clen = outlen < VRF_HW_RATE ? outlen : VRF_HW_RATE;

		keccak_hw_squeeze_bytes(out, clen);
		out += clen;
		outlen -= clen;
		if (outlen > 0) {
			keccak_hw_permute_pulse();
		}
	}
}

static void
sha3_256_hw(uint8_t h[32], const uint8_t *in, size_t inlen)
{
	keccak_hw_hash(in, inlen, 0x06, h, 32);
}

/* ===================================================================== */
/* Test driver                                                           */
/* ===================================================================== */

static void
print_hex32(const uint8_t h[32])
{
	int i;

	for (i = 0; i < 32; i ++) {
		print_uart_byte(h[i]);
	}
	print_uart("\n");
}

int
main(void)
{
	static uint8_t msg[200];
	static uint8_t sw_out[32], hw_out[32];
	uint32_t cycles_sw, cycles_hw;
	int i, sw_hw_match;

	print_uart("=== keccak-abs-sha3-256-multi-block: SHA3-256, 200-byte msg ===\n");

	for (i = 0; i < 200; i ++) {
		msg[i] = (uint8_t)(i & 0xFF);
	}

	clear_csr(mcountinhibit, 1);

	write_csr(mcycle, 0);
	sha3_256(sw_out, msg, sizeof msg);
	cycles_sw = (uint32_t)read_csr(mcycle);
	print_uart("SW cycles: ");
	print_uart_dec((int)cycles_sw);
	print_uart("\n");

	write_csr(mcycle, 0);
	sha3_256_hw(hw_out, msg, sizeof msg);
	cycles_hw = (uint32_t)read_csr(mcycle);
	print_uart("HW cycles: ");
	print_uart_dec((int)cycles_hw);
	print_uart("\n");

	sw_hw_match = memcmp(sw_out, hw_out, 32) == 0;

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

	if (sw_hw_match) {
		print_uart("[PASS] HW matches SW element-wise (32 bytes)\n");
		return 0;
	}

	print_uart("[FAIL] SHA3-256 multi-block SW/HW mismatch\n");
	print_uart("  SW: "); print_hex32(sw_out);
	print_uart("  HW: "); print_hex32(hw_out);
	return 1;
}
