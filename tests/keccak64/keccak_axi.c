// Keccak Accelerator IP - Loosely
// C Benchmark for the AXI coprocessor 
// Author: Federico Runco
// Partly based on https://github.com/riscv/riscv-crypto/blob/main/benchmarks/sha3/zscrypto_rv64/Keccak.c

#include "inc/uart.h"
#include "encoding.h"
#include "keccak_axi.h"

#define KECCAK_BASE_ADDR 0x50000000

static void KeccakF1600_StatePermute(uint64_t *s)
{
    uint64_t volatile *cryptoState  = (uint64_t volatile *)(KECCAK_BASE_ADDR + KECCAK_DATA_0_REG_OFFSET);
    uint64_t volatile *csreg        = (uint64_t volatile *)(KECCAK_BASE_ADDR + KECCAK_CSREG_REG_OFFSET);

    // Copy crypto state to Keccak AXI accelerator
    cryptoState[0] = s[0];
    cryptoState[1] = s[1];
    cryptoState[2] = s[2];
    cryptoState[3] = s[3];
    cryptoState[4] = s[4];
    cryptoState[5] = s[5];
    cryptoState[6] = s[6];
    cryptoState[7] = s[7];
    cryptoState[8] = s[8];
    cryptoState[9] = s[9];
    cryptoState[10] = s[10];
    cryptoState[11] = s[11];
    cryptoState[12] = s[12];
    cryptoState[13] = s[13];
    cryptoState[14] = s[14];
    cryptoState[15] = s[15];
    cryptoState[16] = s[16];
    cryptoState[17] = s[17];
    cryptoState[18] = s[18];
    cryptoState[19] = s[19];
    cryptoState[20] = s[20];
    cryptoState[21] = s[21];
    cryptoState[22] = s[22];
    cryptoState[23] = s[23];
    cryptoState[24] = s[24];

    // Start permutation
    *csreg |= 1 << KECCAK_CSREG_START_BIT;

    // Wait for permutation and clear start bit at end
    while (((*csreg) & (1 << KECCAK_CSREG_DONE_BIT)) == 0);
    *csreg &= ~(1ULL << KECCAK_CSREG_START_BIT);

    // Copy crypto state from Keccak AXI accellerator
    s[0] = cryptoState[0];
    s[1] = cryptoState[1];
    s[2] = cryptoState[2];
    s[3] = cryptoState[3];
    s[4] = cryptoState[4];
    s[5] = cryptoState[5];
    s[6] = cryptoState[6];
    s[7] = cryptoState[7];
    s[8] = cryptoState[8];
    s[9] = cryptoState[9];
    s[10] = cryptoState[10];
    s[11] = cryptoState[11];
    s[12] = cryptoState[12];
    s[13] = cryptoState[13];
    s[14] = cryptoState[14];
    s[15] = cryptoState[15];
    s[16] = cryptoState[16];
    s[17] = cryptoState[17];
    s[18] = cryptoState[18];
    s[19] = cryptoState[19];
    s[20] = cryptoState[20];
    s[21] = cryptoState[21];
    s[22] = cryptoState[22];
    s[23] = cryptoState[23];
    s[24] = cryptoState[24];
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

    printf("KeccakF1600_StatePermute Benchmark - AXI Accellerator\n");

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