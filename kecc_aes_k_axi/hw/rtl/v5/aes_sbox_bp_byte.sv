//  v4: one of three interchangeable aes_sbox backends (see aes_sbox.sv's
//  header comment and aes_sbox_pkg.sv). This one avoids memories
//  entirely: a pure combinational Boolean-gate network per byte, forward
//  and inverse both present since `inv` is a runtime request field (see
//  spec section 9.5 -- no logic sharing between the two directions is
//  assumed).
//
//  Both circuits below are transcribed gate-for-gate, in the same
//  dependency order, from the Circuit Minimization Work project's
//  size-oriented straight-line programs:
//    forward: https://www.cs.yale.edu/homes/peralta/CircuitStuff/SLP_AES_113.txt
//             (113 gates, depth 27; Boyar/Peralta/Calik)
//    inverse: https://www.cs.yale.edu/homes/peralta/CircuitStuff/Sinv.txt
//             (121 gates, depth 21; Boyar/Peralta)
//  See https://www.cs.yale.edu/homes/peralta/CircuitStuff/CMT.html for the
//  project this is from. Operator translation: `+` (source) = XOR = `^`,
//  `x` = AND = `&`, `#` = XNOR = `~^`. Bit numbering is the source's own
//  convention: U0 = data_i's MSB ... U7 = data_i's LSB; each circuit's own
//  S0..S7 = data_o's MSB..LSB -- verified exhaustively against FIPS-197
//  for all 256 input bytes in testbench/tb_aes_sbox.cpp (this bit-mapping
//  is exactly the part the spec that requested this module flagged as
//  most error-prone; if that test ever fails, re-check U*/S* <-> bit
//  mapping before touching any equation below).
//
//  This is unmasked combinational logic -- not side-channel resistant
//  (power/EM analysis, glitches, fault injection all apply). Masking would
//  need a different architecture, extra randomness, and its own
//  verification; out of scope here.
//
//  Attribution/licensing: the straight-line programs above are published
//  by the Circuit Minimization Work project (Yale University); no
//  explicit software license is stated on that page. This is a direct,
//  mechanical transcription of their published gate lists into
//  SystemVerilog. Cite Boyar/Peralta/Calik's work (and the CMT project
//  itself) wherever this module is described; this is NOT Secworks-
//  derived code and does not carry the Secworks BSD license the other
//  aes_sbox_*.sv backends do.

`default_nettype none

module aes_sbox_bp_byte (
                          input  wire        inv,
                          input  wire [7:0]  data_i,
                          output wire [7:0]  data_o
                         );

  // Source convention: U0 is data_i's MSB, U7 its LSB.
  wire U0 = data_i[7];
  wire U1 = data_i[6];
  wire U2 = data_i[5];
  wire U3 = data_i[4];
  wire U4 = data_i[3];
  wire U5 = data_i[2];
  wire U6 = data_i[1];
  wire U7 = data_i[0];

  //----------------------------------------------------------------
  // Forward S-box (SLP_AES_113.txt, 113 gates). The source's own output
  // names (S0..S7) are renamed fs0..fs7 here only because this module
  // also needs the inverse circuit's S0..S7 in the same scope -- every
  // other signal name and every gate/dependency below is unchanged from
  // the source.
  //----------------------------------------------------------------
  wire y14 = U3 ^ U5;
  wire y13 = U0 ^ U6;
  wire y9  = U0 ^ U3;
  wire y8  = U0 ^ U5;
  wire t0  = U1 ^ U2;
  wire y1  = t0 ^ U7;
  wire y4  = y1 ^ U3;
  wire y12 = y13 ^ y14;
  wire y2  = y1 ^ U0;
  wire y5  = y1 ^ U6;
  wire y3  = y5 ^ y8;
  wire t1  = U4 ^ y12;
  wire y15 = t1 ^ U5;
  wire y20 = t1 ^ U1;
  wire y6  = y15 ^ U7;
  wire y10 = y15 ^ t0;
  wire y11 = y20 ^ y9;
  wire y7  = U7 ^ y11;
  wire y17 = y10 ^ y11;
  wire y19 = y10 ^ y8;
  wire y16 = t0 ^ y11;
  wire y21 = y13 ^ y16;
  wire y18 = U0 ^ y16;
  wire t2  = y12 & y15;
  wire t3  = y3 & y6;
  wire t4  = t3 ^ t2;
  wire t5  = y4 & U7;
  wire t6  = t5 ^ t2;
  wire t7  = y13 & y16;
  wire t8  = y5 & y1;
  wire t9  = t8 ^ t7;
  wire t10 = y2 & y7;
  wire t11 = t10 ^ t7;
  wire t12 = y9 & y11;
  wire t13 = y14 & y17;
  wire t14 = t13 ^ t12;
  wire t15 = y8 & y10;
  wire t16 = t15 ^ t12;
  wire t17 = t4 ^ y20;
  wire t18 = t6 ^ t16;
  wire t19 = t9 ^ t14;
  wire t20 = t11 ^ t16;
  wire t21 = t17 ^ t14;
  wire t22 = t18 ^ y19;
  wire t23 = t19 ^ y21;
  wire t24 = t20 ^ y18;
  wire t25 = t21 ^ t22;
  wire t26 = t21 & t23;
  wire t27 = t24 ^ t26;
  wire t28 = t25 & t27;
  wire t29 = t28 ^ t22;
  wire t30 = t23 ^ t24;
  wire t31 = t22 ^ t26;
  wire t32 = t31 & t30;
  wire t33 = t32 ^ t24;
  wire t34 = t23 ^ t33;
  wire t35 = t27 ^ t33;
  wire t36 = t24 & t35;
  wire t37 = t36 ^ t34;
  wire t38 = t27 ^ t36;
  wire t39 = t29 & t38;
  wire t40 = t25 ^ t39;
  wire t41 = t40 ^ t37;
  wire t42 = t29 ^ t33;
  wire t43 = t29 ^ t40;
  wire t44 = t33 ^ t37;
  wire t45 = t42 ^ t41;
  wire z0  = t44 & y15;
  wire z1  = t37 & y6;
  wire z2  = t33 & U7;
  wire z3  = t43 & y16;
  wire z4  = t40 & y1;
  wire z5  = t29 & y7;
  wire z6  = t42 & y11;
  wire z7  = t45 & y17;
  wire z8  = t41 & y10;
  wire z9  = t44 & y12;
  wire z10 = t37 & y3;
  wire z11 = t33 & y4;
  wire z12 = t43 & y13;
  wire z13 = t40 & y5;
  wire z14 = t29 & y2;
  wire z15 = t42 & y9;
  wire z16 = t45 & y14;
  wire z17 = t41 & y8;
  wire tc1  = z15 ^ z16;
  wire tc2  = z10 ^ tc1;
  wire tc3  = z9  ^ tc2;
  wire tc4  = z0  ^ z2;
  wire tc5  = z1  ^ z0;
  wire tc6  = z3  ^ z4;
  wire tc7  = z12 ^ tc4;
  wire tc8  = z7  ^ tc6;
  wire tc9  = z8  ^ tc7;
  wire tc10 = tc8 ^ tc9;
  wire tc11 = tc6 ^ tc5;
  wire tc12 = z3  ^ z5;
  wire tc13 = z13 ^ tc1;
  wire tc14 = tc4 ^ tc12;
  wire fs3  = tc3 ^ tc11;
  wire tc16 = z6  ^ tc8;
  wire tc17 = z14 ^ tc10;
  wire tc18 = tc13 ^ tc14;
  wire fs7  = z12 ~^ tc18;
  wire tc20 = z15 ^ tc16;
  wire tc21 = tc2 ^ z11;
  wire fs0  = tc3 ^ tc16;
  wire fs6  = tc10 ~^ tc18;
  wire fs4  = tc14 ^ fs3;
  wire fs1  = fs3 ~^ tc16;
  wire tc26 = tc17 ^ tc20;
  wire fs2  = tc26 ~^ z17;
  wire fs5  = tc21 ^ tc17;

  //----------------------------------------------------------------
  // Inverse S-box (Sinv.txt, 121 gates). Same rename convention: source
  // S0..S7 renamed is0..is7 here.
  //----------------------------------------------------------------
  wire Y0    = U0 ^ U3;
  wire Y2    = U1 ~^ U3;
  wire Y4    = U0 ^ Y2;
  wire RTL0  = U6 ^ U7;
  wire Y1    = Y2 ^ RTL0;
  wire Y7    = U2 ~^ Y1;
  wire RTL1  = U3 ^ U4;
  wire Y6    = U7 ~^ RTL1;
  wire Y3    = Y1 ^ RTL1;
  wire RTL2  = U0 ~^ U2;
  wire Y5    = U5 ^ RTL2;
  wire sa1   = Y0 ^ Y2;
  wire sa0   = Y1 ^ Y3;
  wire sb1   = Y4 ^ Y6;
  wire sb0   = Y5 ^ Y7;
  wire ah    = Y0 ^ Y1;
  wire al    = Y2 ^ Y3;
  wire aa    = sa0 ^ sa1;
  wire bh    = Y4 ^ Y5;
  wire bl    = Y6 ^ Y7;
  wire bb    = sb0 ^ sb1;
  wire ab20  = sa0 ^ sb0;
  wire ab22  = al ^ bl;
  wire ab23  = Y3 ^ Y7;
  wire ab21  = sa1 ^ sb1;
  wire abcd1 = ah & bh;
  wire rr1   = Y0 & Y4;
  wire ph11  = ab20 ^ abcd1;
  wire t01   = Y1 & Y5;
  wire ph01  = t01 ^ abcd1;
  wire abcd2 = al & bl;
  wire r1    = Y2 & Y6;
  wire pl11  = ab22 ^ abcd2;
  wire r2    = Y3 & Y7;
  wire pl01  = r2 ^ abcd2;
  wire r3    = sa0 & sb0;
  wire vr1   = aa & bb;
  wire pr1   = vr1 ^ r3;
  wire wr1   = sa1 & sb1;
  wire qr1   = wr1 ^ r3;
  wire ab0   = ph11 ^ rr1;
  wire ab1   = ph01 ^ ab21;
  wire ab2   = pl11 ^ r1;
  wire ab3   = pl01 ^ qr1;
  wire cp1   = ab0 ^ pr1;
  wire cp2   = ab1 ^ qr1;
  wire cp3   = ab2 ^ pr1;
  wire cp4   = ab3 ^ ab23;
  wire tinv1 = cp3 ^ cp4;
  wire tinv2 = cp3 & cp1;
  wire tinv3 = cp2 ^ tinv2;
  wire tinv4 = cp1 ^ cp2;
  wire tinv5 = cp4 ^ tinv2;
  wire tinv6 = tinv5 & tinv4;
  wire tinv7 = tinv3 & tinv1;
  wire d2    = cp4 ^ tinv7;
  wire d0    = cp2 ^ tinv6;
  wire tinv8 = cp1 & cp4;
  wire tinv9 = tinv4 & tinv8;
  wire tinv10 = tinv4 ^ tinv2;
  wire d1    = tinv9 ^ tinv10;
  wire tinv11 = cp2 & cp3;
  wire tinv12 = tinv1 & tinv11;
  wire tinv13 = tinv1 ^ tinv2;
  wire d3    = tinv12 ^ tinv13;
  wire sd1   = d1 ^ d3;
  wire sd0   = d0 ^ d2;
  wire dl    = d0 ^ d1;
  wire dh    = d2 ^ d3;
  wire dd    = sd0 ^ sd1;
  wire abcd3 = dh & bh;
  wire rr2   = d3 & Y4;
  wire t02   = d2 & Y5;
  wire abcd4 = dl & bl;
  wire r4    = d1 & Y6;
  wire r5    = d0 & Y7;
  wire r6    = sd0 & sb0;
  wire vr2   = dd & bb;
  wire wr2   = sd1 & sb1;
  wire abcd5 = dh & ah;
  wire r7    = d3 & Y0;
  wire r8    = d2 & Y1;
  wire abcd6 = dl & al;
  wire r9    = d1 & Y2;
  wire r10   = d0 & Y3;
  wire r11   = sd0 & sa0;
  wire vr3   = dd & aa;
  wire wr3   = sd1 & sa1;
  wire ph12  = rr2 ^ abcd3;
  wire ph02  = t02 ^ abcd3;
  wire pl12  = r4 ^ abcd4;
  wire pl02  = r5 ^ abcd4;
  wire pr2   = vr2 ^ r6;
  wire qr2   = wr2 ^ r6;
  wire p0    = ph12 ^ pr2;
  wire p1    = ph02 ^ qr2;
  wire p2    = pl12 ^ pr2;
  wire p3    = pl02 ^ qr2;
  wire ph13  = r7 ^ abcd5;
  wire ph03  = r8 ^ abcd5;
  wire pl13  = r9 ^ abcd6;
  wire pl03  = r10 ^ abcd6;
  wire pr3   = vr3 ^ r11;
  wire qr3   = wr3 ^ r11;
  wire p4    = ph13 ^ pr3;
  wire is7   = ph03 ^ qr3;
  wire p6    = pl13 ^ pr3;
  wire p7    = pl03 ^ qr3;
  wire is3   = p1 ^ p6;
  wire is6   = p2 ^ p6;
  wire is0   = p3 ^ p6;
  wire X11   = p0 ^ p2;
  wire is5   = is0 ^ X11;
  wire X13   = p4 ^ p7;
  wire X14   = X11 ^ X13;
  wire is1   = is3 ^ X14;
  wire X16   = p1 ^ is7;
  wire is2   = X14 ^ X16;
  wire X18   = p0 ^ p4;
  wire X19   = is5 ^ X16;
  wire is4   = X18 ^ X19;

  //----------------------------------------------------------------
  // Separate forward/inverse results, one final direction mux -- see
  // spec section 9.4/9.5: no logic sharing assumed between directions.
  //----------------------------------------------------------------
  wire [7:0] forward_result = {fs0, fs1, fs2, fs3, fs4, fs5, fs6, fs7};
  wire [7:0] inverse_result = {is0, is1, is2, is3, is4, is5, is6, is7};

  assign data_o = inv ? inverse_result : forward_result;

endmodule // aes_sbox_bp_byte

//======================================================================
// EOF aes_sbox_bp_byte.sv
//======================================================================
