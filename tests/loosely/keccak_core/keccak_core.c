// Keccak-f[1600] permutation core benchmark, loosely-coupled AXI accelerator
// (kecc_aes_k_axi, v2 RTL). Same KAT vector as tests/software/keccak_core.c
// and tests/tightly/keccak_core.c, so all three trees check the identical
// input/output pair -- only the primitive implementation differs.
//
// The driver takes the 1600-bit state as a raw uint8_t[200] buffer; casting
// the uint64_t[25] KAT arrays to (uint8_t *) relies on this machine being
// little-endian (RISC-V) and the driver treating that buffer as 25 native
// uint64_t words in memory order -- see kecc_aes_k_axi/sw/kecc_aes_k_axi.c.

#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "kecc_aes_k_axi.h"

int main()
{
    static uint64_t Din[25], D_expected[25], Dout[25];
    unsigned long cycles, instrs;
    int errors = 0;

    memset(Din, 0, sizeof(Din));
    Din[0]  = 0xEC4AFF517369C667ULL;
    Din[1]  = 0x00000010ABBACD29ULL;
    Din[15] = 0x8000000000000000ULL;

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

    printf("Keccak-f[1600] Permutation Core Benchmark - Loosely (kecc_aes_k_axi v2)\n");

    BENCH_ENABLE();
    BENCH_START();
    kecc_aes_k_axi_keccak_permute((const uint8_t *)Din, (uint8_t *)Dout);
    BENCH_READ(cycles, instrs);

    printf("cycles=%lu instrs=%lu\n", cycles, instrs);

    for (int i = 0; i < 25; i++) {
        if (Dout[i] != D_expected[i]) {
            printf("!!! Mismatch at index %d: expected 0x%016llx, got 0x%016llx !!!\n", i, D_expected[i], Dout[i]);
            errors++;
        }
    }

    if (errors == 0)    printf("Keccak-f[1600] Permutation Core Benchmark terminated with no errors.\n");
    else                printf("Keccak-f[1600] Permutation Core Benchmark terminated with %d errors\n", errors);

    return errors;
}
