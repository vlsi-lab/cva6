// kecc_aes_k_xif Accelerator IP
// Full AES-128 single-block encrypt + decrypt using the AES64 coprocessor
// instructions (aes64es/esm/ds/dsm/ks2/im/ks1i), checked against the
// standard FIPS-197 Appendix B test vector:
//   key       = 000102030405060708090a0b0c0d0e0f
//   plaintext = 00112233445566778899aabbccddeeff
//   ciphertext= 69c4e0d86a7b0430d8cdb78070b4c55a
//
// The round/key-schedule sequence below (operand ordering for the "swapped"
// second half of each aes64es/esm/ds/dsm/ks2 call, aes64ks1i round-constant
// indexing starting at 0, which round keys get aes64im-transformed for
// decryption, etc.) mirrors aes-ext/cva6/additional_files/aes_single_block/
// aes_asm.h's proven AES_Cipher/AES_InvCipher/KeyExpansion_ENC/DEC routines,
// re-verified independently against the FIPS-197 vector before being ported
// here (only the instruction encoding changed: .insn-based instead of real
// Zknd/Zkne mnemonics, since this coprocessor offloads them via CV-X-IF
// instead of executing on the native `aes` functional unit).

#include "inc/uart.h"
#include "inc/aes64_copro.h"
#include "encoding.h"

#define NR 10   // AES-128: 10 rounds, 11 round keys (22 uint64_t halves)

// Key expansion (encryption schedule): rk[2*i]/rk[2*i+1] = round i's hi/lo halves.
// aes64ks1i's round number is encoded into the instruction word, so this must
// be unrolled with literal constants -- it cannot be a runtime loop variable.
static void aes128_key_expansion_enc(uint64_t key0, uint64_t key1, uint64_t rk[2 * (NR + 1)])
{
    uint64_t a2 = key0, a3 = key1, t0;
    rk[0] = a2;
    rk[1] = a3;

#define KS_ROUND(rnum) \
    AES64KS1I(t0, a3, rnum); \
    a2 = aes64ks2(t0, a2); \
    a3 = aes64ks2(a2, a3); \
    rk[2 * (rnum) + 2] = a2; \
    rk[2 * (rnum) + 3] = a3;

    KS_ROUND(0)
    KS_ROUND(1)
    KS_ROUND(2)
    KS_ROUND(3)
    KS_ROUND(4)
    KS_ROUND(5)
    KS_ROUND(6)
    KS_ROUND(7)
    KS_ROUND(8)
    KS_ROUND(9)
#undef KS_ROUND
}

// Decryption key schedule: same round keys, but rounds 1..NR-1 get aes64im applied
// to both halves (equivalent-inverse-cipher form), rounds 0 and NR stay untouched.
static void aes128_key_expansion_dec(const uint64_t enc_rk[2 * (NR + 1)], uint64_t dec_rk[2 * (NR + 1)])
{
    dec_rk[0] = enc_rk[0];
    dec_rk[1] = enc_rk[1];
    for (int i = 1; i < NR; i++) {
        dec_rk[2 * i]     = aes64im(enc_rk[2 * i]);
        dec_rk[2 * i + 1] = aes64im(enc_rk[2 * i + 1]);
    }
    dec_rk[2 * NR]     = enc_rk[2 * NR];
    dec_rk[2 * NR + 1] = enc_rk[2 * NR + 1];
}

static void aes128_encrypt(const uint64_t rk[2 * (NR + 1)], uint64_t pt0, uint64_t pt1,
                            uint64_t *ct0, uint64_t *ct1)
{
    uint64_t hi = pt0 ^ rk[0];
    uint64_t lo = pt1 ^ rk[1];

    for (int i = 1; i < NR; i++) {
        uint64_t new_hi = aes64esm(hi, lo);
        uint64_t new_lo = aes64esm(lo, hi);
        hi = new_hi ^ rk[2 * i];
        lo = new_lo ^ rk[2 * i + 1];
    }
    uint64_t new_hi = aes64es(hi, lo);
    uint64_t new_lo = aes64es(lo, hi);
    *ct0 = new_hi ^ rk[2 * NR];
    *ct1 = new_lo ^ rk[2 * NR + 1];
}

static void aes128_decrypt(const uint64_t dec_rk[2 * (NR + 1)], uint64_t ct0, uint64_t ct1,
                            uint64_t *pt0, uint64_t *pt1)
{
    uint64_t hi = ct0 ^ dec_rk[2 * NR];
    uint64_t lo = ct1 ^ dec_rk[2 * NR + 1];

    for (int i = NR - 1; i >= 1; i--) {
        uint64_t new_hi = aes64dsm(hi, lo);
        uint64_t new_lo = aes64dsm(lo, hi);
        hi = new_hi ^ dec_rk[2 * i];
        lo = new_lo ^ dec_rk[2 * i + 1];
    }
    uint64_t new_hi = aes64ds(hi, lo);
    uint64_t new_lo = aes64ds(lo, hi);
    *pt0 = new_hi ^ dec_rk[0];
    *pt1 = new_lo ^ dec_rk[1];
}

int main()
{
    // Bytes 0-7 / 8-15 of each hex string, loaded little-endian (as `ld` would).
    const uint64_t key0 = 0x0706050403020100ULL;  // 00 01 02 03 04 05 06 07
    const uint64_t key1 = 0x0f0e0d0c0b0a0908ULL;  // 08 09 0a 0b 0c 0d 0e 0f
    const uint64_t pt0  = 0x7766554433221100ULL;  // 00 11 22 33 44 55 66 77
    const uint64_t pt1  = 0xffeeddccbbaa9988ULL;  // 88 99 aa bb cc dd ee ff
    const uint64_t exp_ct0 = 0x30047b6ad8e0c469ULL;  // 69 c4 e0 d8 6a 7b 04 30
    const uint64_t exp_ct1 = 0x5ac5b47080b7cdd8ULL;  // d8 cd b7 80 70 b4 c5 5a

    uint64_t enc_rk[2 * (NR + 1)];
    uint64_t dec_rk[2 * (NR + 1)];
    uint64_t ct0, ct1, pt0_out, pt1_out;
    int errors = 0;

    printf("AES-128 single-block encrypt/decrypt Benchmark - kecc_aes_k_xif AES64\n");

    aes128_key_expansion_enc(key0, key1, enc_rk);
    aes128_key_expansion_dec(enc_rk, dec_rk);

    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);
    aes128_encrypt(enc_rk, pt0, pt1, &ct0, &ct1);
    int enc_cycles = read_csr(mcycle);

    write_csr(mcycle, 0);
    aes128_decrypt(dec_rk, ct0, ct1, &pt0_out, &pt1_out);
    int dec_cycles = read_csr(mcycle);

    printf("Encrypt cycles: %d, Decrypt cycles: %d\n", enc_cycles, dec_cycles);

    if (ct0 != exp_ct0 || ct1 != exp_ct1) {
        printf("!!! Ciphertext mismatch: expected 0x%016llx%016llx, got 0x%016llx%016llx !!!\n",
               exp_ct0, exp_ct1, ct0, ct1);
        errors++;
    }
    if (pt0_out != pt0 || pt1_out != pt1) {
        printf("!!! Decrypted plaintext mismatch: expected 0x%016llx%016llx, got 0x%016llx%016llx !!!\n",
               pt0, pt1, pt0_out, pt1_out);
        errors++;
    }

    if (errors == 0) printf("AES-128 Benchmark terminated with no errors.\n");
    else              printf("AES-128 Benchmark terminated with %d errors\n", errors);

    return errors;
}
