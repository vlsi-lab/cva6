#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "fips202.h"
#include "../inc/hash_ip.h"
#include <inttypes.h>
#include "encoding.h"


#ifndef SW_TEST_ENABLED
#define SW_TEST_ENABLED 1
#endif

static int verify_hash(const uint8_t *result, const uint8_t *expected, size_t len) {
    if (memcmp(result, expected, len) == 0) {
        return 1;
    }

    printf("[FAIL] SHA3-256 single block\n");
    printf("  Expected: ");
    for (size_t i = 0; i < (len < 16 ? len : 16); i++) {
        printf("%02x", expected[i]);
    }
    if (len > 16) {
        printf("...");
    }
    printf("\n  Got:      ");
    for (size_t i = 0; i < (len < 16 ? len : 16); i++) {
        printf("%02x", result[i]);
    }
    if (len > 16) {
        printf("...");
    }
    printf("\n");
    return 0;
}

int main(void) {
    uint8_t sw_hash[32];
    uint8_t hw_hash[32];
    const uint8_t msg[] = "abc";
    const uint8_t expected[32] = {
        0x3a, 0x98, 0x5d, 0xa7, 0x4f, 0xe2, 0x25, 0xb2,
        0x04, 0x5c, 0x17, 0x2d, 0x6b, 0xd3, 0x90, 0xbd,
        0x85, 0x5f, 0x08, 0x6e, 0x3e, 0x9d, 0x52, 0x5b,
        0x46, 0xbf, 0xe2, 0x45, 0x11, 0x43, 0x15, 0x32
    };
    uint32_t cycles_sw = 0;
    uint32_t cycles_hw = 0;
    int all_passed = 1;

    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);

    printf("   KECCAK ABS SHA3-256 SINGLE BLOCK TEST\n");

#if SW_TEST_ENABLED
    write_csr(mcycle, 0);
    sha3_256(sw_hash, msg, sizeof(msg) - 1);
    cycles_sw = (uint32_t)read_csr(mcycle);
    all_passed &= verify_hash(sw_hash, expected, sizeof(expected));
    printf("SW cycles: %u\n", cycles_sw);
#else
    printf("--- SOFTWARE TEST SKIPPED ---\n");
#endif

    write_csr(mcycle, 0);
    sha3_256_hw(hw_hash, msg, sizeof(msg) - 1);
    cycles_hw = (uint32_t)read_csr(mcycle);
    all_passed &= verify_hash(hw_hash, expected, sizeof(expected));
    printf("HW cycles: %u\n", cycles_hw);

#if SW_TEST_ENABLED
    all_passed &= verify_hash(hw_hash, sw_hash, sizeof(sw_hash));
    printf("SW Cycles: %u | HW Cycles: %u\n", cycles_sw, cycles_hw);
    if (cycles_sw > 0 && cycles_hw > 0) {
        printf("Speedup: %u.%02ux\n", cycles_sw / cycles_hw, ((cycles_sw * 100U) / cycles_hw) % 100U);
    }
#endif

    if (all_passed) {
        printf("FINAL STATUS: ALL TESTS PASSED\n");
        return EXIT_SUCCESS;
    }

    printf("FINAL STATUS: TEST FAILURE DETECTED\n");
    return 0;
}
