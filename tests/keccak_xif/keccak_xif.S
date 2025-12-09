# rolw rd, rs1, rs2 -> .insn r CUSTOM_3, 0x1, 0x0, rd, rs1, rs2
.macro  XOR3 rd, rs1, rs2, rs3
    .insn r4 MADD, 0x00, 0x02, \rd, \rs1, \rs2, \rs3
.endm
  
.globl main

main:
	li a0, 0xCAFEBABE;
	li a1, 0xDEADBEEF;
	li a2, 0xF00DBABE;
  nop;
  nop;

	XOR3 a4, a0, a1, a2;
  
  
  li a1, 0xE45EBEEF;
  xor a2, a3, a1;
  beqz a2, pass;

fail:
  li a0, 0x1;
  jal exit;

pass:
  li a0, 0x0;
  jal exit;

.data