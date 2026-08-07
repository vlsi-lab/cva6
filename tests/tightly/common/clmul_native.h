// RISC-V Zbc (bit-manipulation carry-less-multiply) native instructions.
// C header exporting `clmul`/`clmulh` as inline-asm macros -- these are
// REAL natively-decoded B-extension instructions (core/multiplier.sv's
// gen_bitmanip block, CVA6ConfigBExtEn=1), not a kecc_aes_k_xif coprocessor
// primitive. No coprocessor RTL is required for this path (a dedicated
// GHASH_CLMULL/GHASH_CLMULH coprocessor instruction pair was prototyped and
// measured against this native path -- identical instruction count, no
// cycle advantage, see tests/result.md's "Results -- GHASH block-multiply"
// -- and removed; this tree now uses the native instructions instead).
//
// Emitted here via `.insn r` (numeric opcode/funct3/funct7) instead of the
// real mnemonics, so this builds regardless of the toolchain's B-extension
// assembler support. Numeric encoding confirmed against this repo's own
// decoder: core/decoder.sv's CLMUL/CLMULH case arms (opcode OP = 0x33 per
// core/include/riscv_pkg.sv's `OpcodeOp`, funct7 = 7'b000_0101 = 0x05,
// funct3 = 3'b001 for clmul / 3'b011 for clmulh).
//
// Identical to tests/native_clmul/common/clmul_native.h -- duplicated here
// (tree-local) rather than shared, matching this repo's existing convention
// (tests/software/common/ghash.c and tests/tightly/common/ghash.c are
// likewise independent per-tree copies, not a shared header).

#ifndef __CLMUL_NATIVE_H__
#define __CLMUL_NATIVE_H__

#include <stdint.h>

#define CLMUL(rd, rs1, rs2) \
    asm volatile (".insn r 0x33, 0x1, 0x05, %0, %1, %2" \
        : "=r" (rd) : "r" (rs1), "r" (rs2))

#define CLMULH(rd, rs1, rs2) \
    asm volatile (".insn r 0x33, 0x3, 0x05, %0, %1, %2" \
        : "=r" (rd) : "r" (rs1), "r" (rs2))

// Low 64 bits of the carry-less (GF(2)-polynomial) product of rs1 and rs2.
static inline uint64_t clmul(uint64_t rs1, uint64_t rs2)  { uint64_t rd; CLMUL(rd, rs1, rs2);  return rd; }
// High 64 bits of the carry-less (GF(2)-polynomial) product of rs1 and rs2.
static inline uint64_t clmulh(uint64_t rs1, uint64_t rs2) { uint64_t rd; CLMULH(rd, rs1, rs2); return rd; }

#endif
