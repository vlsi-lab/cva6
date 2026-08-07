//  Reference: unmodified copy from secworks/aes
//  (see https://github.com/secworks/aesaes), with its own decipher_ctrl FSM
//  and block/sword/round registers removed -- this module is now pure
//  combinational datapath (the round-transform functions below, byte for
//  byte unchanged), driven every cycle by aes_core's single unified
//  controller and its shared working-block register (see aes_core.sv).
//  Also lost its private aes_inv_sbox instance -- sboxw/new_sboxw now go to
//  the aes_sbox module shared with key expansion and encipherment
//  (aes_core selects the inverse table there via `inv` whenever this
//  module's output is the one in use).

//======================================================================
//
// aes_decipher_block.sv
// --------------------
// The AES decipher round. A pure combinational module that implements
// the initial round, main round and final round logic for
// decciper operations.
//
//
// Author: Joachim Strombergson
// Copyright (c) 2013, 2014, Secworks Sweden AB
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or
// without modification, are permitted provided that the following
// conditions are met:
//
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in
//    the documentation and/or other materials provided with the
//    distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
// FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
// COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
// BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
// STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//======================================================================

`default_nettype none

module aes_decipher_block(
                          input wire [2 : 0]    update_type,  //  NO/INIT/SBOX/MAIN/FINAL_UPDATE
                          input wire [1 : 0]    sword_ctr,    //  which word SBOX_UPDATE is substituting this cycle

                          input wire [127 : 0]  block,        //  external ciphertext (INIT_UPDATE only)
                          input wire [127 : 0]  old_block,    //  aes_core's shared working-block register
                          input wire [127 : 0]  round_key,

                          output wire [31 : 0]  sboxw,
                          input wire  [31 : 0]  new_sboxw,

                          output wire [127 : 0] block_new,
                          output wire           block_w0_we,
                          output wire           block_w1_we,
                          output wire           block_w2_we,
                          output wire           block_w3_we
                         );


  //----------------------------------------------------------------
  // Internal constant and parameter definitions.
  //----------------------------------------------------------------
  localparam NO_UPDATE    = 3'h0;
  localparam INIT_UPDATE  = 3'h1;
  localparam SBOX_UPDATE  = 3'h2;
  localparam MAIN_UPDATE  = 3'h3;
  localparam FINAL_UPDATE = 3'h4;


  //----------------------------------------------------------------
  // Gaolis multiplication functions for Inverse MixColumn.
  //----------------------------------------------------------------
  function automatic [7 : 0] gm2(input [7 : 0] op);
    begin
      gm2 = {op[6 : 0], 1'b0} ^ (8'h1b & {8{op[7]}});
    end
  endfunction // gm2

  function automatic [7 : 0] gm3(input [7 : 0] op);
    begin
      gm3 = gm2(op) ^ op;
    end
  endfunction // gm3

  function automatic [7 : 0] gm4(input [7 : 0] op);
    begin
      gm4 = gm2(gm2(op));
    end
  endfunction // gm4

  function automatic [7 : 0] gm8(input [7 : 0] op);
    begin
      gm8 = gm2(gm4(op));
    end
  endfunction // gm8

  function automatic [7 : 0] gm09(input [7 : 0] op);
    begin
      gm09 = gm8(op) ^ op;
    end
  endfunction // gm09

  function automatic [7 : 0] gm11(input [7 : 0] op);
    begin
      gm11 = gm8(op) ^ gm2(op) ^ op;
    end
  endfunction // gm11

  function automatic [7 : 0] gm13(input [7 : 0] op);
    begin
      gm13 = gm8(op) ^ gm4(op) ^ op;
    end
  endfunction // gm13

  function automatic [7 : 0] gm14(input [7 : 0] op);
    begin
      gm14 = gm8(op) ^ gm4(op) ^ gm2(op);
    end
  endfunction // gm14

  function automatic [31 : 0] inv_mixw(input [31 : 0] w);
    reg [7 : 0] b0, b1, b2, b3;
    reg [7 : 0] mb0, mb1, mb2, mb3;
    begin
      b0 = w[31 : 24];
      b1 = w[23 : 16];
      b2 = w[15 : 08];
      b3 = w[07 : 00];

      mb0 = gm14(b0) ^ gm11(b1) ^ gm13(b2) ^ gm09(b3);
      mb1 = gm09(b0) ^ gm14(b1) ^ gm11(b2) ^ gm13(b3);
      mb2 = gm13(b0) ^ gm09(b1) ^ gm14(b2) ^ gm11(b3);
      mb3 = gm11(b0) ^ gm13(b1) ^ gm09(b2) ^ gm14(b3);

      inv_mixw = {mb0, mb1, mb2, mb3};
    end
  endfunction // mixw

  function automatic [127 : 0] inv_mixcolumns(input [127 : 0] data);
    reg [31 : 0] w0, w1, w2, w3;
    reg [31 : 0] ws0, ws1, ws2, ws3;
    begin
      w0 = data[127 : 096];
      w1 = data[095 : 064];
      w2 = data[063 : 032];
      w3 = data[031 : 000];

      ws0 = inv_mixw(w0);
      ws1 = inv_mixw(w1);
      ws2 = inv_mixw(w2);
      ws3 = inv_mixw(w3);

      inv_mixcolumns = {ws0, ws1, ws2, ws3};
    end
  endfunction // inv_mixcolumns

  function automatic [127 : 0] inv_shiftrows(input [127 : 0] data);
    reg [31 : 0] w0, w1, w2, w3;
    reg [31 : 0] ws0, ws1, ws2, ws3;
    begin
      w0 = data[127 : 096];
      w1 = data[095 : 064];
      w2 = data[063 : 032];
      w3 = data[031 : 000];

      ws0 = {w0[31 : 24], w3[23 : 16], w2[15 : 08], w1[07 : 00]};
      ws1 = {w1[31 : 24], w0[23 : 16], w3[15 : 08], w2[07 : 00]};
      ws2 = {w2[31 : 24], w1[23 : 16], w0[15 : 08], w3[07 : 00]};
      ws3 = {w3[31 : 24], w2[23 : 16], w1[15 : 08], w0[07 : 00]};

      inv_shiftrows = {ws0, ws1, ws2, ws3};
    end
  endfunction // inv_shiftrows

  function automatic [127 : 0] addroundkey(input [127 : 0] data, input [127 : 0] rkey);
    begin
      addroundkey = data ^ rkey;
    end
  endfunction // addroundkey


  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  reg [127 : 0] block_new_reg;
  reg           block_w0_we_reg;
  reg           block_w1_we_reg;
  reg           block_w2_we_reg;
  reg           block_w3_we_reg;
  reg [31 : 0]  tmp_sboxw;

  assign block_new   = block_new_reg;
  assign block_w0_we = block_w0_we_reg;
  assign block_w1_we = block_w1_we_reg;
  assign block_w2_we = block_w2_we_reg;
  assign block_w3_we = block_w3_we_reg;
  assign sboxw       = tmp_sboxw;


  //----------------------------------------------------------------
  // round_logic
  //
  // The logic needed to implement init, main and final rounds.
  //----------------------------------------------------------------
  always @*
    begin : round_logic
      reg [127 : 0] inv_shiftrows_block, inv_mixcolumns_block;
      reg [127 : 0] addkey_block;

      inv_shiftrows_block  = 128'h0;
      inv_mixcolumns_block = 128'h0;
      addkey_block         = 128'h0;
      block_new_reg        = 128'h0;
      tmp_sboxw            = 32'h0;
      block_w0_we_reg      = 1'b0;
      block_w1_we_reg      = 1'b0;
      block_w2_we_reg      = 1'b0;
      block_w3_we_reg      = 1'b0;

      // Update based on update type.
      case (update_type)
        // InitRound
        INIT_UPDATE:
          begin
            addkey_block        = addroundkey(block, round_key);
            inv_shiftrows_block = inv_shiftrows(addkey_block);
            block_new_reg       = inv_shiftrows_block;
            block_w0_we_reg     = 1'b1;
            block_w1_we_reg     = 1'b1;
            block_w2_we_reg     = 1'b1;
            block_w3_we_reg     = 1'b1;
          end

        SBOX_UPDATE:
          begin
            block_new_reg = {new_sboxw, new_sboxw, new_sboxw, new_sboxw};

            case (sword_ctr)
              2'h0:
                begin
                  tmp_sboxw       = old_block[127 : 096];
                  block_w0_we_reg = 1'b1;
                end

              2'h1:
                begin
                  tmp_sboxw       = old_block[095 : 064];
                  block_w1_we_reg = 1'b1;
                end

              2'h2:
                begin
                  tmp_sboxw       = old_block[063 : 032];
                  block_w2_we_reg = 1'b1;
                end

              2'h3:
                begin
                  tmp_sboxw       = old_block[031 : 000];
                  block_w3_we_reg = 1'b1;
                end
            endcase // case (sword_ctr)
          end

        MAIN_UPDATE:
          begin
            addkey_block         = addroundkey(old_block, round_key);
            inv_mixcolumns_block = inv_mixcolumns(addkey_block);
            inv_shiftrows_block  = inv_shiftrows(inv_mixcolumns_block);
            block_new_reg        = inv_shiftrows_block;
            block_w0_we_reg      = 1'b1;
            block_w1_we_reg      = 1'b1;
            block_w2_we_reg      = 1'b1;
            block_w3_we_reg      = 1'b1;
          end

        FINAL_UPDATE:
          begin
            block_new_reg   = addroundkey(old_block, round_key);
            block_w0_we_reg = 1'b1;
            block_w1_we_reg = 1'b1;
            block_w2_we_reg = 1'b1;
            block_w3_we_reg = 1'b1;
          end

        default:
          begin
          end
      endcase // case (update_type)
    end // round_logic

endmodule // aes_decipher_block

//======================================================================
// EOF aes_decipher_block.sv
//======================================================================
