// Ascon Accelerator IP - Loosely
// C benchmark for the Ascon permutation (P12) with the round function
// implemented in an external RV64 assembly file (ascon_p12.S).

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "encoding.h"
#include "inc/uart.h"

// P12 permutation, implemented in ascon_p12.S
extern void P12(uint64_t *s);

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

    printf("Ascon P12 Benchmark - External ASM permutation\n");

    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);
    P12(Din);
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
