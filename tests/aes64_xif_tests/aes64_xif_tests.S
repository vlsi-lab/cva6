// kecc_aes_k_xif Accelerator IP
// CV-X-IF ASM Tests for the AES64 instructions (aes64es/esm/ds/dsm/ks2/im/ks1i)
//
// AES64 keeps the real ratified Zknd/Zkne opcode encoding (see
// kecc_aes_k_xif/hw/include/kecc_aes_k_xif_instr_pkg.sv), offloaded to the
// coprocessor via core/decoder.sv's CV-X-IF illegal-instruction fallback
// instead of the native `aes` functional unit. Instructions are emitted with
// `.insn r`/`.insn i` using the numeric opcode/funct3/funct7 encoding so the
// test doesn't depend on the toolchain's K-extension mnemonic support.
//
// Expected results were computed with an independent Python reference model
// of the Sail semantics documented in kecc_aes_k_xif_aes64.sv (standard AES
// S-box / MixColumn tables), for rs1=0x0011223344556677, rs2=0x8899AABBCCDDEEFF.

.macro aes64es rd, rs1, rs2
    .insn r 0x33, 0x0, 0x19, \rd, \rs1, \rs2
.endm

.macro aes64esm rd, rs1, rs2
    .insn r 0x33, 0x0, 0x1B, \rd, \rs1, \rs2
.endm

.macro aes64ds rd, rs1, rs2
    .insn r 0x33, 0x0, 0x1D, \rd, \rs1, \rs2
.endm

.macro aes64dsm rd, rs1, rs2
    .insn r 0x33, 0x0, 0x1F, \rd, \rs1, \rs2
.endm

.macro aes64ks2 rd, rs1, rs2
    .insn r 0x33, 0x0, 0x3F, \rd, \rs1, \rs2
.endm

.macro aes64im rd, rs1
    .insn i 0x13, 0x1, \rd, \rs1, 0x300
.endm

.macro aes64ks1i rd, rs1, rnum
    .insn i 0x13, 0x1, \rd, \rs1, (0x310 | \rnum)
.endm

.globl main

main:
	li a0, 0x0011223344556677;  # rs1
	li a1, 0x8899AABBCCDDEEFF;  # rs2

  aes64es a3, a0, a1;
  li a4, 0x1BEE28C3C4C193F5;
  xor a4, a3, a4;
  bnez a4, fail;

  aes64esm a3, a0, a1;
  li a4, 0xAE01A110C5A8545A;
  xor a4, a3, a4;
  bnez a4, fail;

  aes64ds a3, a0, a1;
  li a4, 0x27F9D36652C96202;
  xor a4, a3, a4;
  bnez a4, fail;

  aes64dsm a3, a0, a1;
  li a4, 0x460A644350878DA1;
  xor a4, a3, a4;
  bnez a4, fail;

  aes64ks2 a3, a0, a1;
  li a4, 0x44556677CCCCCCCC;
  xor a4, a3, a4;
  bnez a4, fail;

  aes64im a3, a0;
  li a4, 0xEEBBCC99AAFF88DD;
  xor a4, a3, a4;
  bnez a4, fail;

  # aes64ks1i rnum=0
  aes64ks1i a3, a0, 0;
  li a4, 0xC3638292C3638292;
  xor a4, a3, a4;
  bnez a4, fail;

  # aes64ks1i rnum=5
  aes64ks1i a3, a0, 5;
  li a4, 0xC36382B3C36382B3;
  xor a4, a3, a4;
  bnez a4, fail;

  # aes64ks1i rnum=10 (0xA, last round: no rotation)
  aes64ks1i a3, a0, 10;
  li a4, 0x638293C3638293C3;
  xor a4, a3, a4;
  bnez a4, fail;

pass:
  li a0, 0x0;
  jal exit;

fail:
  li a0, 0x1;
  jal exit;

.data
