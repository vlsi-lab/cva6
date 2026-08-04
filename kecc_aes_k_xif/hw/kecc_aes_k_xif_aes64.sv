///////////////////////////////////////////////////////////////////////
// File: kecc_aes_k_xif_aes64.sv
// Date: 2024-04-02
// Author: Behnam Farnaghinejad <behnam.farnaghinejad@polito.it>
// Ported from aes-ext/cva6/core/crypto/crypto_aes64.sv into the
// kecc_aes_k_xif coprocessor (XLEN taken as a module parameter instead
// of a crypto_instr_pkg-scoped localparam; opcode enum now imported
// from kecc_aes_k_xif_instr_pkg).
// This file contains a converted version of the original
// file from the riscv-crypto repository.
///////////////////////////////////////////////////////////////////////

//------------------------------- Sail model -------------------------------------------
/*
function clause execute (AES64DS(rs2, rs1, rd)) = {
  let sr : bits(64) = aes_rv64_shiftrows_inv(X(rs2)[63..0], X(rs1)[63..0]);
  let wd : bits(64) = sr[63..0];
  X(rd) = aes_apply_inv_sbox_to_each_byte(wd);
  RETIRE_SUCCESS
}

function clause execute (AES64DSM(rs2, rs1, rd)) = {
  let sr : bits(64) = aes_rv64_shiftrows_inv(X(rs2)[63..0], X(rs1)[63..0]);
  let wd : bits(64) = sr[63..0];
  let sb : bits(64) = aes_apply_inv_sbox_to_each_byte(wd);
  X(rd) = aes_mixcolumn_inv(sb[63..32]) @ aes_mixcolumn_inv(sb[31..0]);
  RETIRE_SUCCESS
}

function clause execute (AES64ES(rs2, rs1, rd)) = {
  let sr : bits(64) = aes_rv64_shiftrows_fwd(X(rs2)[63..0], X(rs1)[63..0]);
  let wd : bits(64) = sr[63..0];
  X(rd) = aes_apply_fwd_sbox_to_each_byte(wd);
  RETIRE_SUCCESS
}

function clause execute (AES64ESM(rs2, rs1, rd)) = {
  let sr : bits(64) = aes_rv64_shiftrows_fwd(X(rs2)[63..0], X(rs1)[63..0]);
  let wd : bits(64) = sr[63..0];
  let sb : bits(64) = aes_apply_fwd_sbox_to_each_byte(wd);
  X(rd) = aes_mixcolumn_fwd(sb[63..32]) @ aes_mixcolumn_fwd(sb[31..0]);
  RETIRE_SUCCESS
}

function clause execute (AES64IM(rs1, rd)) = {
  let w0 : bits(32) = aes_mixcolumn_inv(X(rs1)[31.. 0]);
  let w1 : bits(32) = aes_mixcolumn_inv(X(rs1)[63..32]);
  X(rd) = w1 @ w0;
  RETIRE_SUCCESS
}

function clause execute (AES64KS1I(rnum, rs1, rd)) = {
  if(unsigned(rnum) > 10) then {
  handle_illegal(); RETIRE_SUCCESS
  } else {
  let tmp1 : bits(32) = X(rs1)[63..32];
  let rc : bits(32) = aes_decode_rcon(rnum); // round number -> round constant

  let tmp2 : bits(32) = if (rnum ==0xA) then tmp1 else ror32(tmp1, 8);
  let tmp3 : bits(32) = aes_subword_fwd(tmp2);
  let result : bits(64) = (tmp3 ^ rc) @ (tmp3 ^ rc);
  X(rd) = EXTZ(result);
  RETIRE_SUCCESS
  }
}

function clause execute (AES64KS2(rs2, rs1, rd)) = {
  let w0 : bits(32) = X(rs1)[63..32] ^ X(rs2)[31..0];
  let w1 : bits(32) = X(rs1)[63..32] ^ X(rs2)[31..0] ^ X(rs2)[63..32];
  X(rd) = w1 @ w0;
  RETIRE_SUCCESS
}

*/
//-------------------------------------------------------------------------------------
module crypto_aes64
  import kecc_aes_k_xif_instr_pkg::*;
#(
    parameter int unsigned XLEN = 64
)
(
    input  logic                    aes64_en_i,
    input  aes64_t                  aes64_op_i,
    input  logic [XLEN-1:0]  aes64_rs1_i,
    input  logic [XLEN-1:0]  aes64_rs2_i,
    input  logic [3:0]              aes64_rnum_i,
    output logic [XLEN-1:0]  aes64_result_o
);

    // Select I'th byte of X.
    `define BY(X,I) X[7+8*I:8*I]

    logic [7:0] ks1_sb3;
    logic [7:0] ks1_sb2;
    logic [7:0] ks1_sb1;
    logic [7:0] ks1_sb0;

    // --------------------------- Constructing rows from input registers ----------------------------

    logic [31:0] row_0   ;
    logic [31:0] row_1   ;
    logic [31:0] row_2   ;
    logic [31:0] row_3   ;

    assign  row_0   = {`BY(aes64_rs1_i,0),`BY(aes64_rs1_i,4),`BY(aes64_rs2_i,0),`BY(aes64_rs2_i,4)};
    assign  row_1   = {`BY(aes64_rs1_i,1),`BY(aes64_rs1_i,5),`BY(aes64_rs2_i,1),`BY(aes64_rs2_i,5)};
    assign  row_2   = {`BY(aes64_rs1_i,2),`BY(aes64_rs1_i,6),`BY(aes64_rs2_i,2),`BY(aes64_rs2_i,6)};
    assign  row_3   = {`BY(aes64_rs1_i,3),`BY(aes64_rs1_i,7),`BY(aes64_rs2_i,3),`BY(aes64_rs2_i,7)};

    // --------------------------------------- Encryption Phase ---------------------------------------
    //Shift rows
    logic [31:0] fsh_0   ;
    logic [31:0] fsh_1   ;
    logic [31:0] fsh_2   ;
    logic [31:0] fsh_3   ;

    assign  fsh_0   =  row_0;
    assign  fsh_1   = {row_1[23: 0], row_1[31:24]};
    assign  fsh_2   = {row_2[15: 0], row_2[31:16]};
    assign  fsh_3   = {row_3[ 7: 0], row_3[31: 8]};

    //Re-construct columns from rows
    logic [31:0] f_col_1 ;
    logic [31:0] f_col_0 ;
    assign  f_col_1 = {`BY(fsh_3,2),`BY(fsh_2,2),`BY(fsh_1,2),`BY(fsh_0,2)};
    assign  f_col_0 = {`BY(fsh_3,3),`BY(fsh_2,3),`BY(fsh_1,3),`BY(fsh_0,3)};

    logic [63:0] shiftrows_enc ;
    assign  shiftrows_enc = {f_col_1, f_col_0};

    //SBox input/output
    logic [ 7:0] sb_fwd_in  [7:0];
    logic [ 7:0] sb_fwd_out [7:0];

    assign      sb_fwd_in[0]= (aes64_op_i == aes64_ks1i) ? ks1_sb0 : `BY(shiftrows_enc, 0);
    assign      sb_fwd_in[1]= (aes64_op_i == aes64_ks1i) ? ks1_sb1 : `BY(shiftrows_enc, 1);
    assign      sb_fwd_in[2]= (aes64_op_i == aes64_ks1i) ? ks1_sb2 : `BY(shiftrows_enc, 2);
    assign      sb_fwd_in[3]= (aes64_op_i == aes64_ks1i) ? ks1_sb3 : `BY(shiftrows_enc, 3);
    assign      sb_fwd_in[4]=                                        `BY(shiftrows_enc, 4);
    assign      sb_fwd_in[5]=                                        `BY(shiftrows_enc, 5);
    assign      sb_fwd_in[6]=                                        `BY(shiftrows_enc, 6);
    assign      sb_fwd_in[7]=                                        `BY(shiftrows_enc, 7);

    riscv_crypto_aes_fwd_sbox i_fwd_sbox0 (
        .in(sb_fwd_in [0]),
        .fx(sb_fwd_out[0])
    );
    riscv_crypto_aes_fwd_sbox i_fwd_sbox1 (
        .in(sb_fwd_in [1]),
        .fx(sb_fwd_out[1])
    );
    riscv_crypto_aes_fwd_sbox i_fwd_sbox2 (
        .in(sb_fwd_in [2]),
        .fx(sb_fwd_out[2])
    );
    riscv_crypto_aes_fwd_sbox i_fwd_sbox3 (
        .in(sb_fwd_in [3]),
        .fx(sb_fwd_out[3])
    );
    riscv_crypto_aes_fwd_sbox i_fwd_sbox4 (
        .in(sb_fwd_in [4]),
        .fx(sb_fwd_out[4])
    );
    riscv_crypto_aes_fwd_sbox i_fwd_sbox5 (
        .in(sb_fwd_in [5]),
        .fx(sb_fwd_out[5])
    );
    riscv_crypto_aes_fwd_sbox i_fwd_sbox6 (
        .in(sb_fwd_in [6]),
        .fx(sb_fwd_out[6])
    );
    riscv_crypto_aes_fwd_sbox i_fwd_sbox7 (
        .in(sb_fwd_in [7]),
        .fx(sb_fwd_out[7])
    );

    logic [63:0] e_sbout;
    assign  e_sbout     = {
        sb_fwd_out[7], sb_fwd_out[6], sb_fwd_out[5], sb_fwd_out[4],
        sb_fwd_out[3], sb_fwd_out[2], sb_fwd_out[1], sb_fwd_out[0]
    };

    //MixColumns
    logic [31:0] mix_enc_i0  ;
    logic [31:0] mix_enc_i1  ;

    assign  mix_enc_i0  =   e_sbout[31: 0];
    assign  mix_enc_i1  =   e_sbout[63:32];

    logic [31:0] mix_enc_o0  ;
    logic [31:0] mix_enc_o1  ;

    crypto_aes_mixcolumn_enc i_mix_e0(
        .column_in (mix_enc_i0),
        .column_out(mix_enc_o0)
    );
    crypto_aes_mixcolumn_enc i_mix_e1(
        .column_in (mix_enc_i1),
        .column_out(mix_enc_o1)
    );

    // --------------------------------------- Decryption Phase ---------------------------------------

    //Shift rows
    logic [31:0] ish_0   ;
    logic [31:0] ish_1   ;
    logic [31:0] ish_2   ;
    logic [31:0] ish_3   ;

    assign  ish_0   =  row_0;
    assign  ish_1   = {row_1[ 7: 0], row_1[31: 8]};
    assign  ish_2   = {row_2[15: 0], row_2[31:16]};
    assign  ish_3   = {row_3[23: 0], row_3[31:24]};

    logic [31:0] i_col_1 ;
    logic [31:0] i_col_0 ;

    assign  i_col_1 = {`BY(ish_3,2),`BY(ish_2,2),`BY(ish_1,2),`BY(ish_0,2)};
    assign  i_col_0 = {`BY(ish_3,3),`BY(ish_2,3),`BY(ish_1,3),`BY(ish_0,3)};

    logic [63:0] shiftrows_dec ;
    assign  shiftrows_dec = {i_col_1, i_col_0};

    //SBox input/output
    logic [ 7:0] sb_inv_in  [7:0];
    logic [ 7:0] sb_inv_out [7:0];

    assign      sb_inv_in[0]= `BY(shiftrows_dec, 0);
    assign      sb_inv_in[1]= `BY(shiftrows_dec, 1);
    assign      sb_inv_in[2]= `BY(shiftrows_dec, 2);
    assign      sb_inv_in[3]= `BY(shiftrows_dec, 3);
    assign      sb_inv_in[4]= `BY(shiftrows_dec, 4);
    assign      sb_inv_in[5]= `BY(shiftrows_dec, 5);
    assign      sb_inv_in[6]= `BY(shiftrows_dec, 6);
    assign      sb_inv_in[7]= `BY(shiftrows_dec, 7);

    riscv_crypto_aes_inv_sbox i_inv_sbox0 (
        .in(sb_inv_in [0]),
        .fx(sb_inv_out[0])
    );
    riscv_crypto_aes_inv_sbox i_inv_sbox1 (
        .in(sb_inv_in [1]),
        .fx(sb_inv_out[1])
    );
    riscv_crypto_aes_inv_sbox i_inv_sbox2 (
        .in(sb_inv_in [2]),
        .fx(sb_inv_out[2])
    );
    riscv_crypto_aes_inv_sbox i_inv_sbox3 (
        .in(sb_inv_in [3]),
        .fx(sb_inv_out[3])
    );
    riscv_crypto_aes_inv_sbox i_inv_sbox4 (
        .in(sb_inv_in [4]),
        .fx(sb_inv_out[4])
    );
    riscv_crypto_aes_inv_sbox i_inv_sbox5 (
        .in(sb_inv_in [5]),
        .fx(sb_inv_out[5])
    );
    riscv_crypto_aes_inv_sbox i_inv_sbox6 (
        .in(sb_inv_in [6]),
        .fx(sb_inv_out[6])
    );
    riscv_crypto_aes_inv_sbox i_inv_sbox7 (
        .in(sb_inv_in [7]),
        .fx(sb_inv_out[7])
    );

    logic [63:0] d_sbout;
    assign  d_sbout     = {
        sb_inv_out[7], sb_inv_out[6], sb_inv_out[5], sb_inv_out[4],
        sb_inv_out[3], sb_inv_out[2], sb_inv_out[1], sb_inv_out[0]
    };

    //MixColumns
    logic [31:0] mix_dec_i0  ;
    logic [31:0] mix_dec_i1  ;

    assign  mix_dec_i0  = (aes64_op_i == aes64_im) ? aes64_rs1_i[31: 0] : d_sbout[31: 0];
    assign  mix_dec_i1  = (aes64_op_i == aes64_im) ? aes64_rs1_i[63:32] : d_sbout[63:32];

    logic [31:0] mix_dec_o0  ;
    logic [31:0] mix_dec_o1  ;

    crypto_aes_mixcolumn_dec i_mix_d0(
        .column_in (mix_dec_i0),
        .column_out(mix_dec_o0)
    );
    crypto_aes_mixcolumn_dec i_mix_d1(
        .column_in (mix_dec_i1),
        .column_out(mix_dec_o1)
    );

    // --------------------------------------- Key Schedule ---------------------------------------

    //Round Constants
    localparam logic [7:0] rcon [0:15] = '{8'h01, 8'h02, 8'h04, 8'h08, 8'h10, 8'h20, 8'h40, 8'h80, 8'h1b, 8'h36, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};

    logic [3:0] enc_rcon;
    logic rcon_rot;
    logic [7:0] rconst;

    logic [31:0] ks1_sbout;

    assign enc_rcon = aes64_rnum_i;
    assign rcon_rot = enc_rcon != 4'hA;
    assign rconst = rcon_rot ? rcon[enc_rcon] : 8'b0;

    assign ks1_sb3 = rcon_rot ? aes64_rs1_i[39:32] : aes64_rs1_i[63:56];
    assign ks1_sb2 = rcon_rot ? aes64_rs1_i[63:56] : aes64_rs1_i[55:48];
    assign ks1_sb1 = rcon_rot ? aes64_rs1_i[55:48] : aes64_rs1_i[47:40];
    assign ks1_sb0 = rcon_rot ? aes64_rs1_i[47:40] : aes64_rs1_i[39:32];

    assign ks1_sbout = e_sbout[31:0] ^ {24'b0, rconst};


    // --------------------------------------- Result gathering ---------------------------------------

    logic [63:0] result_ks1;
    assign result_ks1 = {ks1_sbout, ks1_sbout};

    logic [63:0] result_ks2;
    assign result_ks2 = {
        aes64_rs1_i[63:32] ^ aes64_rs2_i[63:32] ^ aes64_rs2_i[31:0],
        aes64_rs1_i[63:32] ^ aes64_rs2_i[31:0]
    };

    logic [63:0] result_enc;
    logic [63:0] result_dec;
    logic [63:0] result_imix;

    always_comb begin
        case (aes64_op_i)
            aes64_ks1i: result_enc = {ks1_sbout, ks1_sbout};
            aes64_ks2:  result_enc = {
                aes64_rs1_i[63:32] ^ aes64_rs2_i[63:32] ^ aes64_rs2_i[31:0],
                aes64_rs1_i[63:32] ^ aes64_rs2_i[31:0]
            };
            aes64_es:   result_enc = e_sbout;
            aes64_esm:  result_enc = {mix_enc_o1, mix_enc_o0};
            aes64_ds:   result_dec = d_sbout;
            aes64_dsm:  result_dec = {mix_dec_o1, mix_dec_o0};
            aes64_im:   result_imix = {mix_dec_o1, mix_dec_o0};
            default:    result_enc = 64'b0;
        endcase
    end

    always_comb begin
        if (aes64_en_i) begin
            case (aes64_op_i)
                aes64_ks1i: aes64_result_o = result_ks1;
                aes64_ks2:  aes64_result_o = result_ks2;
                aes64_es,
                aes64_esm:  aes64_result_o = result_enc;
                aes64_ds,
                aes64_dsm:  aes64_result_o = result_dec;
                aes64_im:   aes64_result_o = result_imix;
                default:    aes64_result_o = 0;
            endcase
        end else begin
            aes64_result_o = 0;
        end
    end

    `undef BY

endmodule
