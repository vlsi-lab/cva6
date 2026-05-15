// Copyright 2025 PoliTO - EDGE Group, @VLSI Lab
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// HASH coprocessor 25x64-bit register file. One 64-bit lane = one Keccak lane.
//
// Write priority (highest first):
//   init          : zero all lanes
//   wb_enable     : overwrite all 25 lanes from wb_data_i
//   write_enable  : lane[index] <= data_i
//   xor_enable    : lane[index] <= lane[index] ^ data_i

module hash_register #(
  parameter int unsigned NUM_LANES = 25,
  parameter int unsigned LANE_W    = 64
) (
  input  logic                                clk_i,
  input  logic                                rst_ni,

  // Write port
  input  logic [LANE_W-1:0]                   data_i,
  input  logic [4:0]                          index_i,        // 0..24
  input  logic                                write_enable_i, // OP_LOAD
  input  logic                                xor_enable_i,   // OP_KABSORB
  input  logic                                init_i,         // OP_INIT

  // Bulk writeback (KPERM result or SPHINCS+ result)
  input  logic                                wb_enable_i,
  input  logic [0:NUM_LANES-1][LANE_W-1:0]    wb_data_i,

  // Read views
  output logic [0:NUM_LANES-1][LANE_W-1:0]    lanes_o,        // 64-bit view
  output logic [0:2*NUM_LANES-1][31:0]        lanes32_o       // 32-bit slice view
);

  logic [LANE_W-1:0] reg_q [0:NUM_LANES-1];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < NUM_LANES; i++) reg_q[i] <= '0;
    end else if (init_i) begin
      for (int i = 0; i < NUM_LANES; i++) reg_q[i] <= '0;
    end else if (wb_enable_i) begin
      for (int i = 0; i < NUM_LANES; i++) reg_q[i] <= wb_data_i[i];
    end else if (write_enable_i) begin
      reg_q[index_i] <= data_i;
    end else if (xor_enable_i) begin
      reg_q[index_i] <= reg_q[index_i] ^ data_i;
    end
  end

  // Read views
  always_comb begin
    for (int i = 0; i < NUM_LANES; i++) begin
      lanes_o[i]          = reg_q[i];
      lanes32_o[2*i]      = reg_q[i][31:0];
      lanes32_o[2*i + 1]  = reg_q[i][63:32];
    end
  end

endmodule
