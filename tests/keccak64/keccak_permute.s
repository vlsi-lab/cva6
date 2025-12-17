# Keccak Accellerator IP - Tightly
# Assembly state permutation function
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

.macro XOR5 dest, a, b, c, d, e
    .insn r4 MADD, 0x0, 0x02, \dest, \a, \b, \c
    .insn r4 MADD, 0x0, 0x02, \dest, \dest, \d, \e
.endm

.macro XANDN dest, a, b, c
    .insn r4 MADD, 0x01, 0x02, \dest, \a, \b, \c
.endm

.macro DXROL3 dest, a, b, c, shamt
    .if \shamt == 0
        .insn r4 MADD, 0x2, 0x02, \dest, \a, \b, \c
    .else
        .insn r4 MADD, 0x2, 0x02, \dest, \a, \b, \c
        rori \dest, \dest, (64 - \shamt)
    .endif
.endm

# TODO: change registers 
.set s00 a0
.set s01 a1
.set s02 a2
.set s03 a3
.set s04 a4
.set s05 t0
.set s06 t1
.set s07 t2
.set s08 t3
.set s09 t4
.set s10 t5
.set s11 t6
.set s12 t7
.set s13 t8
.set s14 s0
.set s15 s1
.set s16 s2
.set s17 s3
.set s18 s4
.set s19 s5
.set s20 s6
.set s21 s7
.set s22 s8
.set s23 s9
.set s24 s10
.set C0 t1
.set C1 t3
.set C2 t4
.set C3 t5
.set C4 t6
.set C5 t7


.align 2
.global KeccakF1600_StatePermute
	# Save context
    addi sp, sp, -8*19
    sd s0,   0*8(sp)
    sd s1,   1*8(sp)
    sd s2,   2*8(sp)
    sd s3,   3*8(sp)
    sd s4,   4*8(sp)
    sd s5,   5*8(sp)
    sd s6,   6*8(sp)
    sd s7,   7*8(sp)
    sd s8,   8*8(sp)
    sd s9,   9*8(sp)
    sd s10, 10*8(sp)
    sd s11, 11*8(sp)
    sd gp,  12*8(sp)
    sd tp,  13*8(sp)
    sd ra,  14*8(sp)
    sd a0,  15*8(sp)
    # 16*8(sp) loop variable
    sd a1,  17*8(sp)

    sd a0, 16*8(sp)
    # Load state from memory
    ld s00, 0(a0)    # s[0]
    ld s01, 8(a0)    # s[1]
    ld s02, 16(a0)   # s[2]
    ld s03, 24(a0)   # s[3]
    ld s04, 32(a0)   # s[4]
    ld s05, 40(a0)   # s[5]
    ld s06, 48(a0)   # s[6]
    ld s07, 56(a0)   # s[7]
    ld s08, 64(a0)   # s[8]
    ld s09, 72(a0)   # s[9]
    ld s10, 80(a0)   # s[10]
    ld s11, 88(a0)   # s[11]
    ld s12, 96(a0)   # s[12]
    ld s13, 104(a0)  # s[13]
    ld s14, 112(a0)  # s[14]
    ld s15, 120(a0)  # s[15]
    ld s16, 128(a0)  # s[16]
    ld s17, 136(a0)  # s[17]
    ld s18, 144(a0)  # s[18]
    ld s19, 152(a0)  # s[19]
    ld s20, 160(a0)  # s[20]
    ld s21, 168(a0)  # s[21]
    ld s22, 176(a0)  # s[22]
    ld s23, 184(a0)  # s[23]
    ld s24, 192(a0)  # s[24]

    li loop_i, 24 
single_round:
	XOR5 C1, s01, s06, s11, s16, s21
    XOR5 C2, s02, s07, s12, s17, s22
    XOR5 C3, s04, s09, s14, s19, s24
    XOR5 C4, s03, s08, s13, s18, s23

	mv C5, s05
	DXROL3 s05, s03, C2, C3, 28
    DXROL3 s03, s18, C2, C3, 21
    DXROL3 s18, s17, C1, C4, 15
    DXROL3 s17, s11, C0, C2, 10
    DXROL3 s11, s07, C1, C4, 6
    DXROL3 s07, s10, C3, C1, 3
    DXROL3 s10, s01, C0, C2, 1
    DXROL3 s01, s06, C0, C2, 44
    DXROL3 s06, s09, C4, C0, 20
    DXROL3 s09, s22, C1, C4, 61
    DXROL3 s22, s14, C4, C0, 39
    DXROL3 s14, s20, C3, C1, 18
    DXROL3 s20, s02, C1, C4, 62
    DXROL3 s02, s12, C1, C4, 43
    DXROL3 s12, s13, C2, C3, 25
    DXROL3 s13, s19, C4, C0, 8
    DXROL3 s19, s23, C2, C3, 56
    DXROL3 s23, s15, C3, C1, 41
    DXROL3 s15, s04, C4, C0, 27
    DXROL3 s04, s24, C4, C0, 14
    DXROL3 s24, s21, C0, C2, 2
    DXROL3 s21, s08, C2, C3, 55
    DXROL3 s08, s16, C0, C2, 45
    DXROL3 s16, C5, C3, C1, 36
    DXROL3 s00, s00, C3, C1, 0

	mv C0, s04
    XANDN s04, s04, s00, s01
    XANDN s01, s01, s02, s03
    XANDN s03, s03, s04, s00
    XANDN s00, s00, s01, s02
    XANDN s02, s02, s03, C0

	mv C0, s09
    XANDN s09, s09, s05, s06
    XANDN s06, s06, s07, s08
    XANDN s08, s08, s09, s05
    XANDN s05, s05, s06, s07
    XANDN s07, s07, s08, C0

	mv C0, s14
    XANDN s14, s14, s10, s11
    XANDN s11, s11, s12, s13
    XANDN s13, s13, s14, s10
    XANDN s10, s10, s11, s12
    XANDN s12, s12, s13, C0

    mv C0, s19
    XANDN s19, s19, s15, s16
    XANDN s16, s16, s17, s18
    XANDN s18, s18, s19, s15
    XANDN s15, s15, s16, s17
    XANDN s17, s17, s18, C0
	
    mv C0, s24
    XANDN s24, s24, s20, s21
    XANDN s21, s21, s22, s23
    XANDN s23, s23, s24, s20
    XANDN s20, s20, s21, s22
    XANDN s22, s22, s23, C0

	# s00 ^= KeccakP1600RoundConstants[round];
    addi loop_i, -1
    bnez loop_i, single_round

	# TODO: restore context
    addi sp, sp, 8*19
	ret