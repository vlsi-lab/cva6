// Keccak Accelerator IP - Tightly
// CV-X-IF ASM Tests 
// Author: Federico Runco

.macro xor3 rd, rs1, rs2, rs3
    .insn r4 CUSTOM_1, 0x00, 0x02, \rd, \rs1, \rs2, \rs3
.endm

.macro xandn dest, a, b, c
    .insn r4 CUSTOM_1, 0x01, 0x02, \dest, \a, \b, \c
.endm

.macro rxri rd, rs1, rs2, rs3, shamt
  .if \shamt < 32
    .insn r4 CUSTOM_2, (\shamt & 0x7), ((\shamt >> 3) & 0x3), \rd, \rs1, \rs2, \rs3
  .else
    .insn r4 CUSTOM_3, ((\shamt - 32) & 0x7), (((\shamt - 32) >> 3) & 0x3), \rd, \rs1, \rs2, \rs3
  .endif
.endm
  
.globl main

main:
	li a0, 0xCAFEBABE;
	li a1, 0xDEADBEEF;
	li a2, 0xF00DBABE;

  xor3 a3, a0, a1, a2; 
  li a4, 0xE45EBEEF;
  xor a4, a3, a4;
  bnez a4, fail;

  xandn a3, a0, a1, a2;
  li a4, 0xEAFEBAAE;
  xor a4, a3, a4;
  bnez a4, fail; 

  # rxri.l
  rxri a3, a0, a1, a2, 13;
  li a4, 0x00003e890e25a000;
  xor a4, a3, a4;
  bnez a4, fail;

  # rxri.h
  rxri a3, a0, a1, a2, 54;
  li a4, 0x4b400000007d121c;
  xor a4, a3, a4;
  bnez a4, fail;

  # rxri.l no final rotation
  rxri a3, a0, a1, a2, 0;
  li a4, 0x00000001f448712d;
  xor a4, a3, a4;
  bnez a4, fail;

pass:
  li a0, 0x0;
  jal exit;

fail:
  li a0, 0x1;
  jal exit;

.data