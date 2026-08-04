# Keccak Accelerator IP - Tightly
# ASM Implementation of the Keccak-f[1600] Permutation utilizing coprocessor instructions
# Author: Federico Runco

.data
.align 2
round_constants:
.quad 0x0000000000000001
.quad 0x0000000000008082
.quad 0x800000000000808a
.quad 0x8000000080008000
.quad 0x000000000000808b
.quad 0x0000000080000001
.quad 0x8000000080008081
.quad 0x8000000000008009
.quad 0x000000000000008a
.quad 0x0000000000000088
.quad 0x0000000080008009
.quad 0x000000008000000a
.quad 0x000000008000808b
.quad 0x800000000000008b
.quad 0x8000000000008089
.quad 0x8000000000008003
.quad 0x8000000000008002
.quad 0x8000000000000080
.quad 0x000000000000800a
.quad 0x800000008000000a
.quad 0x8000000080008081
.quad 0x8000000000008080
.quad 0x0000000080000001
.quad 0x8000000080008008

.text

.macro xor5 dest, a, b, c, d, e
    .insn r4 CUSTOM_1, 0x0, 0x02, \dest, \a, \b, \c
    .insn r4 CUSTOM_1, 0x0, 0x02, \dest, \dest, \d, \e
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


.macro LoadCryptoState S00, S01, S02, S03, S04, S05, S06, S07, S08, S09, S10, S11, S12, S13, S14, S15, S16, S17, S18, S19, S20, S21, S22, S23, S24
    ld \S00, 0*8(a0)
    ld \S01, 1*8(a0)
    ld \S02, 2*8(a0)
    ld \S03, 3*8(a0)
    ld \S04, 4*8(a0)
    ld \S05, 5*8(a0)
    ld \S06, 6*8(a0)
    ld \S07, 7*8(a0)
    ld \S08, 8*8(a0)
    ld \S09, 9*8(a0)
    ld \S10, 10*8(a0)
    ld \S11, 11*8(a0)
    ld \S12, 12*8(a0)
    ld \S13, 13*8(a0)
    ld \S14, 14*8(a0)
    ld \S15, 15*8(a0)
    ld \S16, 16*8(a0)
    ld \S17, 17*8(a0)
    ld \S18, 18*8(a0)
    ld \S19, 19*8(a0)
    ld \S20, 20*8(a0)
    ld \S21, 21*8(a0)
    ld \S22, 22*8(a0)
    ld \S23, 23*8(a0)
    ld \S24, 24*8(a0)
.endm

.macro StoreCryptoState S00, S01, S02, S03, S04, S05, S06, S07, S08, S09, S10, S11, S12, S13, S14, S15, S16, S17, S18, S19, S20, S21, S22, S23, S24
    sd \S00, 0*8(a0)
    sd \S01, 1*8(a0)
    sd \S02, 2*8(a0)
    sd \S03, 3*8(a0)
    sd \S04, 4*8(a0)
    sd \S05, 5*8(a0)
    sd \S06, 6*8(a0)
    sd \S07, 7*8(a0)
    sd \S08, 8*8(a0)
    sd \S09, 9*8(a0)
    sd \S10, 10*8(a0)
    sd \S11, 11*8(a0)
    sd \S12, 12*8(a0)
    sd \S13, 13*8(a0)
    sd \S14, 14*8(a0)
    sd \S15, 15*8(a0)
    sd \S16, 16*8(a0)
    sd \S17, 17*8(a0)
    sd \S18, 18*8(a0)
    sd \S19, 19*8(a0)
    sd \S20, 20*8(a0)
    sd \S21, 21*8(a0)
    sd \S22, 22*8(a0)
    sd \S23, 23*8(a0)
    sd \S24, 24*8(a0)
.endm

.macro SingleRound s00, s01, s02, s03, s04, s05, s06, s07, s08, s09, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19, s20, s21, s22, s23, s24, c0, c1, c2, c3, c4
   	xor5 \c0, \s00, \s05, \s10, \s15, \s20
	xor5 \c1, \s01, \s06, \s11, \s16, \s21
    xor5 \c2, \s02, \s07, \s12, \s17, \s22
    xor5 \c3, \s04, \s09, \s14, \s19, \s24
    xor5 \c4, \s03, \s08, \s13, \s18, \s23

    sd \s05, 18*8(sp) # backup s05
    rxri \s05, \s03, \c2, \c3, 28
    rxri \s03, \s18, \c2, \c3, 21
    rxri \s18, \s17, \c1, \c4, 15
    rxri \s17, \s11, \c0, \c2, 10
    rxri \s11, \s07, \c1, \c4, 6
    rxri \s07, \s10, \c3, \c1, 3
    rxri \s10, \s01, \c0, \c2, 1
    rxri \s01, \s06, \c0, \c2, 44
    rxri \s06, \s09, \c4, \c0, 20
    rxri \s09, \s22, \c1, \c4, 61
    rxri \s22, \s14, \c4, \c0, 39
    rxri \s14, \s20, \c3, \c1, 18
    rxri \s20, \s02, \c1, \c4, 62
    rxri \s02, \s12, \c1, \c4, 43
    rxri \s12, \s13, \c2, \c3, 25
    rxri \s13, \s19, \c4, \c0, 8
    rxri \s19, \s23, \c2, \c3, 56
    rxri \s23, \s15, \c3, \c1, 41
    rxri \s15, \s04, \c4, \c0, 27
    rxri \s04, \s24, \c4, \c0, 14
    rxri \s24, \s21, \c0, \c2, 2
    rxri \s21, \s08, \c2, \c3, 55
    rxri \s08, \s16, \c0, \c2, 45

    ld \c0, 18*8(sp) # restore s05
    rxri \s16, \c0,  \c3, \c1, 36
    rxri \s00, \s00, \c3, \c1, 0

    mv \c0, \s04
    xandn \s04, \s04, \s00, \s01
    xandn \s01, \s01, \s02, \s03
    xandn \s03, \s03, \s04, \s00
    xandn \s00, \s00, \s01, \s02
    xandn \s02, \s02, \s03, \c0

    mv \c0, \s09
    xandn \s09, \s09, \s05, \s06
    xandn \s06, \s06, \s07, \s08
    xandn \s08, \s08, \s09, \s05
    xandn \s05, \s05, \s06, \s07
    xandn \s07, \s07, \s08, \c0

	mv \c0, \s14
    xandn \s14, \s14, \s10, \s11
    xandn \s11, \s11, \s12, \s13
    xandn \s13, \s13, \s14, \s10
    xandn \s10, \s10, \s11, \s12
    xandn \s12, \s12, \s13, \c0

    mv \c0, \s19
    xandn \s19, \s19, \s15, \s16
    xandn \s16, \s16, \s17, \s18
    xandn \s18, \s18, \s19, \s15
    xandn \s15, \s15, \s16, \s17
    xandn \s17, \s17, \s18, \c0
	
    mv \c0, \s24
    xandn \s24, \s24, \s20, \s21
    xandn \s21, \s21, \s22, \s23
    xandn \s23, \s23, \s24, \s20
    xandn \s20, \s20, \s21, \s22
    xandn \s22, \s22, \s23, \c0

    ld \c0, 17*8(sp)
    ld \c1, 0(\c0)
    xor \s00, \s00, \c1
    addi \c0, \c0, 8
    sd \c0, 17*8(sp)
.endm

.globl KeccakF1600_StatePermute
.align 2
KeccakF1600_StatePermute:
    addi sp, sp, -8*19
    # Save callee-saved registers
    sd s0,  0*8(sp)
    sd s1,  1*8(sp)
    sd s2,  2*8(sp)
    sd s3,  3*8(sp)
    sd s4,  4*8(sp)
    sd s5,  5*8(sp)
    sd s6,  6*8(sp)
    sd s7,  7*8(sp)
    sd s8,  8*8(sp)
    sd s9,  9*8(sp)
    sd s10, 10*8(sp)
    sd s11, 11*8(sp)
    sd gp,  12*8(sp)
    sd tp,  13*8(sp)
    sd ra,  14*8(sp)
    sd a0,  15*8(sp)

    la a1, round_constants
    sd a1, 17*8(sp)

    LoadCryptoState a1, a2, a3, a4, a5, a6, a7, t0, t1, t2, t3, t4, t5, t6, s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10
    li a0, 24
    
    rounds_loop:
        sd a0, 16*8(sp)
        SingleRound a1, a2, a3, a4, a5, a6, a7, t0, t1, t2, t3, t4, t5, t6, s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, ra, gp, tp, a0
        ld a0, 16*8(sp)
        addi a0, a0, -1
        bnez a0, rounds_loop

    ld a0, 15*8(sp)
    StoreCryptoState a1, a2, a3, a4, a5, a6, a7, t0, t1, t2, t3, t4, t5, t6, s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10
    
    # Restore callee-saved registers
    ld s0,  0*8(sp)
    ld s1,  1*8(sp)
    ld s2,  2*8(sp)
    ld s3,  3*8(sp)
    ld s4,  4*8(sp)
    ld s5,  5*8(sp)
    ld s6,  6*8(sp)
    ld s7,  7*8(sp)
    ld s8,  8*8(sp)
    ld s9,  9*8(sp)
    ld s10, 10*8(sp)
    ld s11, 11*8(sp)
    ld gp,  12*8(sp)
    ld tp,  13*8(sp)
    ld ra,  14*8(sp)
    addi sp, sp, 8*19
    ret
