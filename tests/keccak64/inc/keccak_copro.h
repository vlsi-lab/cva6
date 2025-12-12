// Keccak Accellerator IP - Tightly
// C Header exporting the defines for the coprocessor instructions 
// Author: Federico Runco

#ifndef __KECCAK_COPRO_H__
#define __KECCAK_COPRO_H__

#define XOR5(dest, a, b, c, d, e) \
    asm volatile ( \
        ".insn r4 MADD, 0x0, 0x02, %[rd], %[r1], %[r2], %[r3]\n" \
        ".insn r4 MADD, 0x0, 0x02, %[rd], %[rd], %[r4], %[r5]" \
        : [rd] "=&r" (dest) \
        : [r1] "r" (a), [r2] "r" (b), [r3] "r" (c), [r4] "r" (d), [r5] "r" (e) \
    );

#define DXROL3(dest, a, b, c, shamt) do { \
    if ((shamt) == 0) { \
        asm volatile ( \
            ".insn r4 MADD, 0x2, 0x02, %[rd], %[r1], %[r2], %[r3]\n" \
            : [rd] "=&r" (dest) \
            : [r1] "r" (a), [r2] "r" (b), [r3] "r" (c) \
        ); \
    } else { \
        asm volatile ( \
            ".insn r4 MADD, 0x2, 0x02, %[rd], %[r1], %[r2], %[r3]\n" \
            "rori %[rd], %[rd], 64-%[rs]" \
            : [rd] "=&r" (dest) \
            : [r1] "r" (a), [r2] "r" (b), [r3] "r" (c), [rs] "i" (shamt) \
        ); \
    } \
} while (0)

#define XANDN(dest, a, b, c) \
    asm volatile ( \
        ".insn r4 MADD, 0x01, 0x02, %[rd], %[r1], %[r2], %[r3]\n" \
        : [rd] "=&r" (dest) \
        : [r1] "r" (a), [r2] "r" (b), [r3] "r" (c) \
    );

#endif