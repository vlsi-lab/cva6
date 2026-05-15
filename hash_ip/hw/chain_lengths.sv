// Copyright 2025 PoliTO - EDGE Group, @VLSI Lab
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Adapted from horcrux/chain_lengths.sv (V. Piscopo, A. Dolmeta) for the
// hash_ip coprocessor on CVA6: imports hash_pkg, exposes the 9-word result
// register array so the top can pack two 32-bit chain-length words into a
// single 64-bit OP_STORE response.

module chain_lengths
  import hash_pkg::*;
#(
  parameter int unsigned NUM_REG32 = 50
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic [0:NUM_REG32-1][31:0]      register_array_i,
  input  hash_pkg::opcode_t               insn_i,
  output logic [0:8][31:0]                result_regs_o,
  output logic                            cl_active_o
);

  // Result registers (max 9 32-bit words for 256f: 64 nibbles + 3 csum nibbles)
  logic [31:0] result_regs [0:8];
  logic        cl_active_reg;

  // ----- nibble extraction (msg in little-endian byte order, hi-nibble first per byte)
  logic [3:0] nibbles [0:63];
  always_comb begin
    for (int r = 0; r < 8; r++) begin
      nibbles[8*r + 0] = register_array_i[r][7:4];
      nibbles[8*r + 1] = register_array_i[r][3:0];
      nibbles[8*r + 2] = register_array_i[r][15:12];
      nibbles[8*r + 3] = register_array_i[r][11:8];
      nibbles[8*r + 4] = register_array_i[r][23:20];
      nibbles[8*r + 5] = register_array_i[r][19:16];
      nibbles[8*r + 6] = register_array_i[r][31:28];
      nibbles[8*r + 7] = register_array_i[r][27:24];
    end
  end

  // ----- checksum trees
  logic [9:0] csum_128f, csum_192f, csum_256f;
  always_comb begin
    csum_128f = '0;
    for (int i = 0; i < 32; i++) csum_128f += (10'd15 - 10'(nibbles[i]));
    csum_192f = '0;
    for (int i = 0; i < 48; i++) csum_192f += (10'd15 - 10'(nibbles[i]));
    csum_256f = '0;
    for (int i = 0; i < 64; i++) csum_256f += (10'd15 - 10'(nibbles[i]));
  end

  // ----- shift csum left by 4 (LEN2=3 nibbles), pack into one word
  logic [15:0] csum_sh_128f, csum_sh_192f, csum_sh_256f;
  assign csum_sh_128f = {6'b0, csum_128f} << 4;
  assign csum_sh_192f = {6'b0, csum_192f} << 4;
  assign csum_sh_256f = {6'b0, csum_256f} << 4;

  logic [31:0] csum_word_128f, csum_word_192f, csum_word_256f;
  assign csum_word_128f = {csum_sh_128f[15:12], csum_sh_128f[11:8], csum_sh_128f[7:4], 20'b0};
  assign csum_word_192f = {csum_sh_192f[15:12], csum_sh_192f[11:8], csum_sh_192f[7:4], 20'b0};
  assign csum_word_256f = {csum_sh_256f[15:12], csum_sh_256f[11:8], csum_sh_256f[7:4], 20'b0};

  // ----- pack message nibbles into 32-bit words
  logic [31:0] packed_msg [0:7];
  always_comb begin
    for (int w = 0; w < 8; w++) begin
      packed_msg[w] = {nibbles[8*w+0], nibbles[8*w+1], nibbles[8*w+2], nibbles[8*w+3],
                       nibbles[8*w+4], nibbles[8*w+5], nibbles[8*w+6], nibbles[8*w+7]};
    end
  end

  // ----- result regs latch
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < 9; i++) result_regs[i] <= '0;
      cl_active_reg <= 1'b0;
    end else begin
      case (insn_i)
        OP_CL_128F: begin
          result_regs[0] <= packed_msg[0];
          result_regs[1] <= packed_msg[1];
          result_regs[2] <= packed_msg[2];
          result_regs[3] <= packed_msg[3];
          result_regs[4] <= csum_word_128f;
          for (int i = 5; i < 9; i++) result_regs[i] <= '0;
          cl_active_reg <= 1'b1;
        end
        OP_CL_192F: begin
          for (int i = 0; i < 6; i++) result_regs[i] <= packed_msg[i];
          result_regs[6] <= csum_word_192f;
          result_regs[7] <= '0;
          result_regs[8] <= '0;
          cl_active_reg <= 1'b1;
        end
        OP_CL_256F: begin
          for (int i = 0; i < 8; i++) result_regs[i] <= packed_msg[i];
          result_regs[8] <= csum_word_256f;
          cl_active_reg <= 1'b1;
        end
        OP_KSTART, OP_INIT,
        OP_THASH1, OP_THASH2, OP_PRF_ADDR,
        OP_THASH1_192, OP_THASH2_192,
        OP_THASH1_256, OP_THASH2_256,
        OP_PRF_192, OP_PRF_256: begin
          cl_active_reg <= 1'b0;
        end
        default: ;
      endcase
    end
  end

  // ----- outputs
  always_comb begin
    for (int i = 0; i < 9; i++) result_regs_o[i] = result_regs[i];
  end
  assign cl_active_o = cl_active_reg;

endmodule
