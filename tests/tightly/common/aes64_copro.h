// kecc_aes_k_xif Accelerator IP
// C header exporting the AES64 coprocessor instructions as inline-asm macros.
//
// AES64 keeps the real ratified Zknd/Zkne opcode encoding, but is emitted here
// via `.insn r`/`.insn i` (numeric opcode/funct3/funct7) instead of the real
// mnemonics, so this builds regardless of the toolchain's K-extension support.
// Numeric encodings match kecc_aes_k_xif/hw/include/kecc_aes_k_xif_instr_pkg.sv.

#ifndef __AES64_COPRO_H__
#define __AES64_COPRO_H__

#include <stdint.h>

#define AES64ES(rd, rs1, rs2) \
    asm volatile (".insn r 0x33, 0x0, 0x19, %0, %1, %2" \
        : "=r" (rd) : "r" (rs1), "r" (rs2))

#define AES64ESM(rd, rs1, rs2) \
    asm volatile (".insn r 0x33, 0x0, 0x1B, %0, %1, %2" \
        : "=r" (rd) : "r" (rs1), "r" (rs2))

#define AES64DS(rd, rs1, rs2) \
    asm volatile (".insn r 0x33, 0x0, 0x1D, %0, %1, %2" \
        : "=r" (rd) : "r" (rs1), "r" (rs2))

#define AES64DSM(rd, rs1, rs2) \
    asm volatile (".insn r 0x33, 0x0, 0x1F, %0, %1, %2" \
        : "=r" (rd) : "r" (rs1), "r" (rs2))

#define AES64KS2(rd, rs1, rs2) \
    asm volatile (".insn r 0x33, 0x0, 0x3F, %0, %1, %2" \
        : "=r" (rd) : "r" (rs1), "r" (rs2))

#define AES64IM(rd, rs1) \
    asm volatile (".insn i 0x13, 0x1, %0, %1, 0x300" \
        : "=r" (rd) : "r" (rs1))

// rnum must be a compile-time constant (0-10): it is encoded directly into
// the instruction word, not read from a register.
#define AES64KS1I(rd, rs1, rnum) \
    asm volatile (".insn i 0x13, 0x1, %0, %1, (0x310 | " #rnum ")" \
        : "=r" (rd) : "r" (rs1))

static inline uint64_t aes64es(uint64_t rs1, uint64_t rs2)  { uint64_t rd; AES64ES(rd, rs1, rs2);  return rd; }
static inline uint64_t aes64esm(uint64_t rs1, uint64_t rs2) { uint64_t rd; AES64ESM(rd, rs1, rs2); return rd; }
static inline uint64_t aes64ds(uint64_t rs1, uint64_t rs2)  { uint64_t rd; AES64DS(rd, rs1, rs2);  return rd; }
static inline uint64_t aes64dsm(uint64_t rs1, uint64_t rs2) { uint64_t rd; AES64DSM(rd, rs1, rs2); return rd; }
static inline uint64_t aes64ks2(uint64_t rs1, uint64_t rs2) { uint64_t rd; AES64KS2(rd, rs1, rs2); return rd; }
static inline uint64_t aes64im(uint64_t rs1)                { uint64_t rd; AES64IM(rd, rs1);       return rd; }

#endif
