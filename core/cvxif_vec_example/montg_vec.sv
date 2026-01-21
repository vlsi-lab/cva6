///////////////////////////////////////////////////////////////////////////////////
//
// Copyright 2026 PoliTO - @VLSI Lab
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// HORCRUX: montg.sv
//
// Auth: Alessandra Dolmeta, Valeria Piscopo
// Email: alessandra.dolmeta@polito.it, valeria.piscopo@polito.it
// Affiliation: Politecnico di Torino - @VLSI Lab
//
///////////////////////////////////////////////////////////////////////////////////

module montg_vec
#(
	parameter type opcode_t = logic
) (
    input  logic signed [63:0]        a,
    input  logic signed [63:0]        b,          // currently unused (reserved for R=2^32 variants)
    input  opcode_t                   opcode_i,
    output logic signed [63:0]        result
);

    // ------------------ Moduli (Q) ------------------
    localparam logic signed [31:0] Q_kyber     = 32'sd3329;
    localparam logic signed [31:0] Q_newhope   = 32'sd12289;
    localparam logic signed [31:0] Q_falcon    = 32'sd12289;
    localparam logic signed [31:0] Q_ntru      = 32'sd4591;

    localparam logic [31:0] Q_dilithium    = 32'd8380417;


    // ------------------ QINV (R = 2^16) ------------------
    localparam logic signed [15:0] QINV_kyber   = 16'shF301; // -3327  ≡ 62209 mod 2^16
    localparam logic signed [15:0] QINV_newhope = 16'sd12287; //  12287 ≡ -q^{-1} mod 2^16
    localparam logic signed [15:0] QINV_falcon  = 16'sd12287; //  NewHope (q=12289)
    localparam logic signed [15:0] QINV_ntru    = 16'shC2F1;  // -15631 ≡ 49905 mod 2^16

    localparam logic signed [31:0] QINV_dilithium = 32'd58728449;


    // ---------- add these signals ----------
    logic signed [15:0] a16_1, a16_2, b16_1, b16_2;

    logic signed [31:0] prod0, prod1, prod2, prod3;
    logic signed [31:0] mul0, mul1, mul2, mul3;

    logic signed [15:0] t16_0, t16_1, t16_2, t16_3;

    logic signed [31:0] red0, red1, red2, red3;   // lane reduced (still signed)
    logic signed [15:0] r16_0,  r16_1,  r16_2,  r16_3;

    // (optional) pack 4x16 -> 64
    logic signed [63:0] result_vec;


    logic signed [63:0] a64;
    logic signed [15:0] t16;
    logic signed [31:0] q_sel;
    logic signed [15:0] qinv_sel;
    logic signed [31:0] qinv_sel_32;
    logic signed [31:0] prod;

    // For Barrett (64-bit intermediates)
    logic signed [63:0] prod64, tQ64;
    logic signed [63:0] temp64;
    logic signed [63:0] diff;

    always_comb begin

        a16_1 = a[15:0];  // (int16_t)a
        a16_2 = a[47:32]; // (int16_t)a
        b16_1 = b[15:0];  // (int16_t)b
        b16_2 = b[47:32]; // (int16_t)b


        unique case (opcode_i)

            cvxif_vec_instr_pkg::MONTG_KYBER: begin
                q_sel    = Q_kyber;
                qinv_sel = QINV_kyber;
                qinv_sel_32 = 32'sd0;  
            end

            cvxif_vec_instr_pkg::MONTG_NEWHOPE: begin
                q_sel    = Q_newhope;
                qinv_sel = QINV_newhope;
                qinv_sel_32 = 32'sd0;
            end
            cvxif_vec_instr_pkg::MONTG_FALCON: begin
                q_sel    = Q_falcon;
                qinv_sel = QINV_falcon;
                qinv_sel_32 = 32'sd0;
            end
            cvxif_vec_instr_pkg::MONTG_NTRU: begin
                q_sel    = Q_ntru;
                qinv_sel = QINV_ntru;
                qinv_sel_32 = 32'sd0;
            end
            cvxif_vec_instr_pkg::MONTG_DILITHIUM: begin
                q_sel    = Q_dilithium;
                qinv_sel_32 = QINV_dilithium;
                qinv_sel    = 16'sd0;
            end

            default: begin
                // NOP / 0
                q_sel       = 32'sd0;
                qinv_sel    = 16'sd0;
                qinv_sel_32 = 32'sd0;
   
            end
        endcase
    end

    always_comb begin

        unique case (opcode_i)

            cvxif_vec_instr_pkg::MONTG_KYBER, cvxif_vec_instr_pkg::MONTG_NEWHOPE, cvxif_vec_instr_pkg::MONTG_FALCON, cvxif_vec_instr_pkg::MONTG_NTRU: begin
                //prod = $signed(a16) * $signed(qinv_sel);
                //t16 = prod[15:0];
                //result = ($signed(a) - $signed({{16{t16[15]}}, t16}) * $signed(q_sel)) >>> 16;
                //a64      = 64'sd0;
                //prod64   = 64'sd0;
                //temp64   = 64'sd0;
                //tQ64     = 64'sd0;
                //diff     = 64'sd0;

                // Four independent Montgomery reductions (R = 2^16)
                mul0  = $signed(a16_1) * $signed(qinv_sel);
                t16_0 = mul0[15:0];
                red0  = ($signed(prod0) - $signed({{16{t16_0[15]}}, t16_0}) * $signed(q_sel)) >>> 16;
                r16_0 = red0[15:0];

                // Lane 1: a16_2 * b16_2
                mul1  = $signed(a16_2) * $signed(qinv_sel);
                t16_1 = mul1[15:0];
                red1  = ($signed(prod1) - $signed({{16{t16_1[15]}}, t16_1}) * $signed(q_sel)) >>> 16;
                r16_1 = red1[15:0];

                // Lane 2: a16_1 * b16_2
                mul2  = $signed(b16_1) * $signed(qinv_sel);
                t16_2 = mul2[15:0];
                red2  = ($signed(prod2) - $signed({{16{t16_2[15]}}, t16_2}) * $signed(q_sel)) >>> 16;
                r16_2 = red2[15:0];

                // Lane 3: a16_2 * b16_1
                mul3  = $signed(b16_2) * $signed(qinv_sel);
                t16_3 = mul3[15:0];
                red3  = ($signed(prod3) - $signed({{16{t16_3[15]}}, t16_3}) * $signed(q_sel)) >>> 16;
                r16_3 = red3[15:0];

                // Pack 4x16 into 64-bit result: [63:48]=lane3, [47:32]=lane2, [31:16]=lane1, [15:0]=lane0
                result_vec = {r16_3, r16_2, r16_1, r16_0};

                // Drive outputs / clear unused signals (keep your style)
                // If your module output is still [31:0], you must change it or select two lanes.
                result  = result_vec[63:0];  // example: keep lane0+lane1; change as needed

                a64    = 64'sd0;
                prod64 = 64'sd0;
                temp64 = 64'sd0;
                tQ64   = 64'sd0;
                diff   = 64'sd0;
            end

            cvxif_vec_instr_pkg::MONTG_DILITHIUM: begin
                a64    = { $unsigned(a) };
                prod64 = $signed(a) * qinv_sel_32;
                temp64 = {{32{prod64[31]}}, prod64[31:0]};
                tQ64   = temp64 * q_sel;
                diff   = a64 - tQ64;
                result = diff[63:32];
                prod     = 32'sd0;
                t16      = 16'sd0;
            end

            default: begin
                prod     = 32'sd0;
                a64      = 64'sd0;
                t16      = 16'sd0;
                prod64   = 64'sd0;
                temp64   = 64'sd0;
                diff     = 64'sd0;
                result   = '0;
            end

        endcase

    end

endmodule