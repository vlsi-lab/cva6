// Copyright 2025 PoliTO - EDGE Group, @VLSI Lab
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// HASH coprocessor top compute. Adapted from horcrux.sv but stripped down to
// Keccak + SPHINCS+ + WOTS+ chain-lengths and re-targeted at a 64-bit native
// register file (25 lanes). Reuses the HORCRUX permutation core verbatim.

module hash
  import hash_pkg::*;
#(
  parameter int unsigned NUM_LANES = 25,
  parameter int unsigned LANE_W    = 64
) (
  input  logic                                clk_i,
  input  logic                                rst_ni,

  // Decoded request from XIF EX stage
  input  hash_pkg::opcode_t                   insn_i,
  input  logic [LANE_W-1:0]                   rs1_i,   // data / index / byte_off
  input  logic [LANE_W-1:0]                   rs2_i,   // index / simple_mode
  input  logic                                start_i, // kicks KSTART/KPERM/KABSORB cycle

  // Status / response
  output logic                                done_keccak_o,   // single pulse
  output logic                                done_sphincs_o,  // single pulse
  output logic [LANE_W-1:0]                   rd_o
);

  // ==========================================================================
  // Register file
  // ==========================================================================
  logic [LANE_W-1:0]                  reg_data_in;
  logic [4:0]                         reg_index;
  logic                               reg_we, reg_xor, reg_init, reg_wb_en;
  logic [0:NUM_LANES-1][LANE_W-1:0]   reg_wb_data;
  logic [0:NUM_LANES-1][LANE_W-1:0]   lanes64;
  logic [0:2*NUM_LANES-1][31:0]       lanes32;

  hash_register #(
    .NUM_LANES (NUM_LANES),
    .LANE_W    (LANE_W)
  ) i_reg (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .data_i         (reg_data_in),
    .index_i        (reg_index),
    .write_enable_i (reg_we),
    .xor_enable_i   (reg_xor),
    .init_i         (reg_init),
    .wb_enable_i    (reg_wb_en),
    .wb_data_i      (reg_wb_data),
    .lanes_o        (lanes64),
    .lanes32_o      (lanes32)
  );

  assign reg_data_in = rs1_i;
  assign reg_index   = rs2_i[4:0];
  assign reg_we      = (insn_i == OP_LOAD);
  assign reg_xor     = (insn_i == OP_KABSORB);
  assign reg_init    = (insn_i == OP_INIT);

  // ==========================================================================
  // Keccak permutation core
  // ==========================================================================
  logic [1599:0] keccak_input;
  logic [1599:0] keccak_result;
  logic          keccak_status;
  logic          KSTART;

  // SPHINCS+ unified signals
  logic           sphincs_start_keccak;
  logic [1599:0]  sphincs_keccak_input;
  logic           sphincs_wb_enable;
  logic [0:2*NUM_LANES-1][31:0] sphincs_wb_data; // 32-bit view (50x32)
  logic           sphincs_active;
  logic           sphincs_done;

  // start signal: explicit OP_KSTART/OP_KPERM trigger OR sphincs FSM
  assign KSTART = start_i | sphincs_start_keccak;

  // 1600-bit register flatten (lane 0 -> bits[63:0])
  logic [1599:0] register_array_flat;
  always_comb begin
    register_array_flat = '0;
    for (int i = 0; i < NUM_LANES; i++) begin
      register_array_flat[i*LANE_W +: LANE_W] = lanes64[i];
    end
  end

  always_comb begin
    keccak_input = sphincs_active ? sphincs_keccak_input : register_array_flat;
  end

  keccak_f i_keccak (
    .clk         (clk_i),
    .rst_n       (rst_ni),
    .start_i     (KSTART),
    .Din         (keccak_input),
    .Dout        (keccak_result),
    .status_d    (keccak_status),
    .keccak_intr (done_keccak_o)
  );

  // 32-bit view of keccak result (50 words) - used by sphincs writeback
  logic [0:2*NUM_LANES-1][31:0] keccak_result32;
  always_comb begin
    for (int i = 0; i < 2*NUM_LANES; i++) begin
      keccak_result32[i] = keccak_result[i*32 +: 32];
    end
  end

  // ==========================================================================
  // Keccak writeback latching: pulse on done after a OP_KPERM was issued
  // ==========================================================================
  logic keccak_wb_pending, keccak_writeback;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                       keccak_wb_pending <= 1'b0;
    else if (insn_i == OP_KPERM)       keccak_wb_pending <= 1'b1;
    else if (done_keccak_o)            keccak_wb_pending <= 1'b0;
  end

  assign keccak_writeback = done_keccak_o & keccak_wb_pending;

  // ==========================================================================
  // SPHINCS+ unified ops
  // ==========================================================================
  sphincs_ops #(
    .NUM_VARIABLES  (2*NUM_LANES),
    .VARIABLE_WIDTH (32)
  ) i_sphincs (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .register_array_i       (lanes32),
    .insn_i                 (insn_i),
    .simple_mode_i          (|rs2_i),
    .keccak_done_i          (done_keccak_o),
    .keccak_result_i        (keccak_result32),
    .sphincs_start_keccak_o (sphincs_start_keccak),
    .sphincs_keccak_input_o (sphincs_keccak_input),
    .sphincs_wb_enable_o    (sphincs_wb_enable),
    .sphincs_wb_data_o      (sphincs_wb_data),
    .sphincs_active_o       (sphincs_active),
    .sphincs_done_o         (sphincs_done)
  );

  assign done_sphincs_o = sphincs_done;

  // ==========================================================================
  // Combined writeback into the 64-bit register file
  //   - keccak path: 1600-bit Dout -> 25 lanes
  //   - sphincs path: 50x32 view  -> 25 lanes (pack pairs)
  // ==========================================================================
  always_comb begin
    reg_wb_en = keccak_writeback | sphincs_wb_enable;
    if (sphincs_wb_enable) begin
      for (int i = 0; i < NUM_LANES; i++) begin
        reg_wb_data[i] = {sphincs_wb_data[2*i + 1], sphincs_wb_data[2*i]};
      end
    end else begin
      for (int i = 0; i < NUM_LANES; i++) begin
        reg_wb_data[i] = keccak_result[i*LANE_W +: LANE_W];
      end
    end
  end

  // ==========================================================================
  // Chain lengths (WOTS+)
  // ==========================================================================
  logic [0:8][31:0] cl_results;
  logic             cl_active;

  chain_lengths #(
    .NUM_REG32 (2*NUM_LANES)
  ) i_chain_lengths (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .register_array_i (lanes32),
    .insn_i           (insn_i),
    .result_regs_o    (cl_results),
    .cl_active_o      (cl_active)
  );

  // ==========================================================================
  // OP_KREAD3 - read 3 consecutive bytes from the lane array
  //   rs1[7:3] = lane index, rs1[2:0] = byte offset within lane
  //   3 bytes always fit in a 128-bit window over two adjacent lanes.
  // ==========================================================================
  logic [4:0]   rd3_lane0_idx, rd3_lane1_idx_raw, rd3_lane1_idx;
  logic [2:0]   rd3_byte_pos;
  logic [LANE_W-1:0] rd3_lane0, rd3_lane1;
  logic [127:0] rd3_window, rd3_window_shifted;
  logic [LANE_W-1:0] rd3_result;

  assign rd3_byte_pos      = rs1_i[2:0];
  assign rd3_lane0_idx     = rs1_i[7:3];
  assign rd3_lane1_idx_raw = rs1_i[7:3] + ((|rs1_i[2:0]) ? 5'd1 : 5'd0);
  // Clamp lane1 to last valid lane (high half is don't-care once shifted past end)
  assign rd3_lane1_idx = (rd3_lane1_idx_raw >= NUM_LANES) ? 5'(NUM_LANES-1)
                                                          : rd3_lane1_idx_raw;

  assign rd3_lane0 = lanes64[rd3_lane0_idx];
  assign rd3_lane1 = (rd3_lane1_idx_raw >= NUM_LANES) ? '0 : lanes64[rd3_lane1_idx];
  assign rd3_window = {rd3_lane1, rd3_lane0};
  assign rd3_window_shifted = rd3_window >> ({4'b0, rd3_byte_pos} * 4'd8);
  assign rd3_result = {40'b0, rd3_window_shifted[23:0]};

  // ==========================================================================
  // OP_STORE - 64-bit response
  //   cl_active=1 : pack two consecutive 32-bit chain-length result words
  //   else        : return full 64-bit Keccak lane
  // ==========================================================================
  logic [LANE_W-1:0] store_result;
  always_comb begin
    if (cl_active) begin
      // Map 64-bit lane index rs1[2:0] -> two underlying 32-bit slots in
      // cl_results[0..8]. The high half is zero whenever the low slot is
      // the last entry (csum word for 256f).
      logic [3:0]  idx32_lo;
      logic [31:0] cl_lo, cl_hi;
      idx32_lo = {rs1_i[2:0], 1'b0};                  // 2*lane
      cl_lo    = (idx32_lo > 4'd8) ? 32'h0 : cl_results[idx32_lo];
      cl_hi    = (idx32_lo >= 4'd8) ? 32'h0 : cl_results[idx32_lo + 4'd1];
      store_result = {cl_hi, cl_lo};
    end else begin
      store_result = lanes64[rs1_i[4:0]];
    end
  end

  // ==========================================================================
  // Result mux
  // ==========================================================================
  always_comb begin
    rd_o = '0;
    case (insn_i)
      OP_STORE : rd_o = store_result;
      OP_KREAD3: rd_o = rd3_result;
      default  : rd_o = '0;
    endcase
  end

endmodule
