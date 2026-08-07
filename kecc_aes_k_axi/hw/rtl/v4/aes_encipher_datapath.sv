//  Derived from secworks/aes's aes_encipher_block.v
//  (see https://github.com/secworks/aesaes) -- the round-transform math
//  below (shiftrows/mixcolumns/addroundkey) is unchanged, but this is a
//  *separate* module from aes_encipher_block.sv, not a rewrite of it:
//  aes_encipher_block.sv is still used as-is (own FSM, own registers) by
//  aes_enc128_core.sv, the standalone AES-128-encrypt-only accelerator, so
//  it couldn't be stripped down without breaking that unrelated core. This
//  module is the pure-combinational, FSM-less, register-less twin used
//  instead by aes_core's single unified controller and its shared
//  working-block register (see aes_core.sv) -- same math, no clk/reset_n,
//  no local block/sword/round state of its own.

`default_nettype none

module aes_encipher_datapath(
                             input wire [2 : 0]    update_type,  //  NO/INIT/SBOX/MAIN/FINAL_UPDATE
                             input wire [1 : 0]    sword_ctr,    //  which word SBOX_UPDATE is substituting this cycle

                             input wire [127 : 0]  block,        //  external plaintext (INIT_UPDATE only)
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
  // Round functions with sub functions.
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

  function automatic [31 : 0] mixw(input [31 : 0] w);
    reg [7 : 0] b0, b1, b2, b3;
    reg [7 : 0] mb0, mb1, mb2, mb3;
    begin
      b0 = w[31 : 24];
      b1 = w[23 : 16];
      b2 = w[15 : 08];
      b3 = w[07 : 00];

      mb0 = gm2(b0) ^ gm3(b1) ^ b2      ^ b3;
      mb1 = b0      ^ gm2(b1) ^ gm3(b2) ^ b3;
      mb2 = b0      ^ b1      ^ gm2(b2) ^ gm3(b3);
      mb3 = gm3(b0) ^ b1      ^ b2      ^ gm2(b3);

      mixw = {mb0, mb1, mb2, mb3};
    end
  endfunction // mixw

  function automatic [127 : 0] mixcolumns(input [127 : 0] data);
    reg [31 : 0] w0, w1, w2, w3;
    reg [31 : 0] ws0, ws1, ws2, ws3;
    begin
      w0 = data[127 : 096];
      w1 = data[095 : 064];
      w2 = data[063 : 032];
      w3 = data[031 : 000];

      ws0 = mixw(w0);
      ws1 = mixw(w1);
      ws2 = mixw(w2);
      ws3 = mixw(w3);

      mixcolumns = {ws0, ws1, ws2, ws3};
    end
  endfunction // mixcolumns

  function automatic [127 : 0] shiftrows(input [127 : 0] data);
    reg [31 : 0] w0, w1, w2, w3;
    reg [31 : 0] ws0, ws1, ws2, ws3;
    begin
      w0 = data[127 : 096];
      w1 = data[095 : 064];
      w2 = data[063 : 032];
      w3 = data[031 : 000];

      ws0 = {w0[31 : 24], w1[23 : 16], w2[15 : 08], w3[07 : 00]};
      ws1 = {w1[31 : 24], w2[23 : 16], w3[15 : 08], w0[07 : 00]};
      ws2 = {w2[31 : 24], w3[23 : 16], w0[15 : 08], w1[07 : 00]};
      ws3 = {w3[31 : 24], w0[23 : 16], w1[15 : 08], w2[07 : 00]};

      shiftrows = {ws0, ws1, ws2, ws3};
    end
  endfunction // shiftrows

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
  reg [31 : 0]  muxed_sboxw;

  assign block_new   = block_new_reg;
  assign block_w0_we = block_w0_we_reg;
  assign block_w1_we = block_w1_we_reg;
  assign block_w2_we = block_w2_we_reg;
  assign block_w3_we = block_w3_we_reg;
  assign sboxw       = muxed_sboxw;


  //----------------------------------------------------------------
  // round_logic
  //
  // The logic needed to implement init, main and final rounds.
  //----------------------------------------------------------------
  always @*
    begin : round_logic
      reg [127 : 0] shiftrows_block, mixcolumns_block;
      reg [127 : 0] addkey_init_block, addkey_main_block, addkey_final_block;

      block_new_reg   = 128'h0;
      muxed_sboxw     = 32'h0;
      block_w0_we_reg = 1'b0;
      block_w1_we_reg = 1'b0;
      block_w2_we_reg = 1'b0;
      block_w3_we_reg = 1'b0;

      shiftrows_block    = shiftrows(old_block);
      mixcolumns_block   = mixcolumns(shiftrows_block);
      addkey_init_block  = addroundkey(block, round_key);
      addkey_main_block  = addroundkey(mixcolumns_block, round_key);
      addkey_final_block = addroundkey(shiftrows_block, round_key);

      case (update_type)
        INIT_UPDATE:
          begin
            block_new_reg   = addkey_init_block;
            block_w0_we_reg = 1'b1;
            block_w1_we_reg = 1'b1;
            block_w2_we_reg = 1'b1;
            block_w3_we_reg = 1'b1;
          end

        SBOX_UPDATE:
          begin
            block_new_reg = {new_sboxw, new_sboxw, new_sboxw, new_sboxw};

            case (sword_ctr)
              2'h0:
                begin
                  muxed_sboxw     = old_block[127 : 096];
                  block_w0_we_reg = 1'b1;
                end

              2'h1:
                begin
                  muxed_sboxw     = old_block[095 : 064];
                  block_w1_we_reg = 1'b1;
                end

              2'h2:
                begin
                  muxed_sboxw     = old_block[063 : 032];
                  block_w2_we_reg = 1'b1;
                end

              2'h3:
                begin
                  muxed_sboxw     = old_block[031 : 000];
                  block_w3_we_reg = 1'b1;
                end
            endcase // case (sword_ctr)
          end

        MAIN_UPDATE:
          begin
            block_new_reg   = addkey_main_block;
            block_w0_we_reg = 1'b1;
            block_w1_we_reg = 1'b1;
            block_w2_we_reg = 1'b1;
            block_w3_we_reg = 1'b1;
          end

        FINAL_UPDATE:
          begin
            block_new_reg   = addkey_final_block;
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

endmodule // aes_encipher_datapath

//======================================================================
// EOF aes_encipher_datapath.sv
//======================================================================
