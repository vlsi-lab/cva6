// Ascon Accelerator IP - Loosely
// C Benchmark for the AXI coprocessor
// Ported to mirror keccak_axi.c's structure/benchmark harness.

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "encoding.h"
#include "ascon_axi.h"
#include "inc/uart.h"

#define ASCON_BASE_ADDR 0x50001000

static void AsconP12_StatePermute(uint64_t *s)
{
    uint64_t volatile *cryptoState = (uint64_t volatile *)(ASCON_BASE_ADDR + ASCON_DATA_0_REG_OFFSET);
    uint64_t volatile *csreg       = (uint64_t volatile *)(ASCON_BASE_ADDR + ASCON_CSREG_REG_OFFSET);

    // Copy crypto state to Ascon AXI accelerator
    cryptoState[0] = s[0];
    cryptoState[1] = s[1];
    cryptoState[2] = s[2];
    cryptoState[3] = s[3];
    cryptoState[4] = s[4];

    // Set round count (12) and start permutation
    *csreg = ((uint64_t)12 << ASCON_CSREG_ROUNDS_OFFSET) | (1ULL << ASCON_CSREG_START_BIT);

    // Wait for permutation and clear start bit at end
    while (((*csreg) & (1ULL << ASCON_CSREG_DONE_BIT)) == 0);
    *csreg &= ~(1ULL << ASCON_CSREG_START_BIT);

    // Copy crypto state from Ascon AXI accellerator
    s[0] = cryptoState[0];
    s[1] = cryptoState[1];
    s[2] = cryptoState[2];
    s[3] = cryptoState[3];
    s[4] = cryptoState[4];
}

int main(){
    static uint64_t Din[5], D_expected[5];
    int cycles;
    int errors = 0;

    // Initial state
    memset(Din, 0, sizeof(Din));
    Din[0] = 0x0123456789ABCDEFULL;
    Din[1] = 0xFEDCBA9876543210ULL;
    Din[2] = 0x1111111111111111ULL;
    Din[3] = 0xAAAAAAAAAAAAAAAAULL;
    Din[4] = 0x00000000DEADBEEFULL;

    // Expected state after P12 (computed on the host with the untouched
    // NIST-LWC reference implementation)
    D_expected[0] = 0xdfc62157582c5b09ULL;
    D_expected[1] = 0x6ddb027baeb942f1ULL;
    D_expected[2] = 0xf31c5f11bb27d581ULL;
    D_expected[3] = 0x38ace12e4290287aULL;
    D_expected[4] = 0x79794f839b5628c0ULL;

    printf("Ascon P12 Benchmark - AXI Accellerator\n");

    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);
    AsconP12_StatePermute(Din);
    cycles = read_csr(mcycle);

    printf("Number of clock cycles for Ascon P12: %d\n", cycles);

    for (int i = 0; i < 5; i++) {
        if (Din[i] != D_expected[i]) {
            printf("!!! Mismatch at index %d: expected 0x%016llx, got 0x%016llx !!!\n", i, D_expected[i], Din[i]);
            errors++;
        }
    }

    if (errors == 0)    printf("Ascon P12 Benchmark terminated with no errors.\n");
    else                printf("Ascon P12 Benchmark terminated with %d errors\n", errors);

    return 0;
}
