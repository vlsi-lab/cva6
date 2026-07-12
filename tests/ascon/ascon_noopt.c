// Ascon Accelerator IP - Loosely
// C baseline for the Ascon permutation (P12), no hardware acceleration.
// Round function ported verbatim from the NIST-LWC reference implementation
// (CHIMERA/sw/applications/original/LWC/ASCON/ascon128v12/include/round.h).

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "encoding.h"
#include "inc/uart.h"

#define ROR(x, n) (((x) << (64 - (n))) | ((x) >> (n)))

static void P12(uint64_t *s)
{
    static const uint64_t rc[12] = {
        0xf0, 0xe1, 0xd2, 0xc3, 0xb4, 0xa5, 0x96, 0x87, 0x78, 0x69, 0x5a, 0x4b
    };

    uint64_t s00, s01, s02, s03, s04;

    s00 = s[0];
    s01 = s[1];
    s02 = s[2];
    s03 = s[3];
    s04 = s[4];

    for (int round = 0; round < 12; round++) {
        uint64_t t00, t01, t02, t03, t04;

        s02 ^= rc[round];
        s00 ^= s04;
        s04 ^= s03;
        s02 ^= s01;

        t00 = s00 ^ (~s01 & s02);
        t01 = s01 ^ (~s02 & s03);
        t02 = s02 ^ (~s03 & s04);
        t03 = s03 ^ (~s04 & s00);
        t04 = s04 ^ (~s00 & s01);

        t01 ^= t00;
        t00 ^= t04;
        t03 ^= t02;
        t02 = ~t02;

        s00 = t00 ^ ROR(t00, 19) ^ ROR(t00, 28);
        s01 = t01 ^ ROR(t01, 61) ^ ROR(t01, 39);
        s02 = t02 ^ ROR(t02, 1)  ^ ROR(t02, 6);
        s03 = t03 ^ ROR(t03, 10) ^ ROR(t03, 17);
        s04 = t04 ^ ROR(t04, 7)  ^ ROR(t04, 41);
    }

    s[0] = s00;
    s[1] = s01;
    s[2] = s02;
    s[3] = s03;
    s[4] = s04;
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

    printf("Ascon P12 Benchmark - No Optimizations\n");

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
