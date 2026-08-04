// Keccak Accelerator IP - Tightly
// C Header exporting the defines for the coprocessor instructions 
// Author: Federico Runco

#ifndef __KECCAK_COPRO_H__
#define __KECCAK_COPRO_H__

#define XOR5(dest, a, b, c, d, e) \
    asm volatile ( \
        ".insn r4 CUSTOM_1, 0x0, 0x02, %[rd], %[r1], %[r2], %[r3]\n" \
        ".insn r4 CUSTOM_1, 0x0, 0x02, %[rd], %[rd], %[r4], %[r5]" \
        : [rd] "=&r" (dest) \
        : [r1] "r" (a), [r2] "r" (b), [r3] "r" (c), [r4] "r" (d), [r5] "r" (e) \
    );

#define RXRI(dest, a, b, c, shamt) do { \
    if ((shamt) < 32) { \
        asm volatile ( \
            ".insn r4 CUSTOM_2, %[f3], %[f2], %[rd], %[r1], %[r2], %[r3]\n" \
            : [rd] "=&r" (dest) \
            : [r1] "r" (a), [r2] "r" (b), [r3] "r" (c), \
              [f3] "i" ((shamt) & 0x7), [f2] "i" (((shamt) >> 3) & 0x3) \
        ); \
    } else { \
        asm volatile ( \
            ".insn r4 CUSTOM_3, %[f3], %[f2], %[rd], %[r1], %[r2], %[r3]\n" \
            : [rd] "=&r" (dest) \
            : [r1] "r" (a), [r2] "r" (b), [r3] "r" (c), \
              [f3]"i" (((shamt) - 32) & 0x7), [f2] "i" ((((shamt) - 32) >> 3) & 0x3) \
        ); \
    } \
} while (0)

#define XANDN(dest, a, b, c) \
    asm volatile ( \
        ".insn r4 CUSTOM_1, 0x01, 0x02, %[rd], %[r1], %[r2], %[r3]\n" \
        : [rd] "=&r" (dest) \
        : [r1] "r" (a), [r2] "r" (b), [r3] "r" (c) \
    );

#endif