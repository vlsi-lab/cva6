// Copyright 2025 PoliTO - EDGE Group, @VLSI Lab
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// HASH coprocessor top - CVA6 CV-X-IF interface. Mirrors the structure of
// keccak_ip/hw/keccak_xif.sv: instantiates id/ex/cid sub-blocks, gates
// issue_ready while a multi-cycle op is in flight.

module hash_xif
  import hash_pkg::*;
#(
  parameter int unsigned NrRgprPorts        = 3,
  parameter int unsigned XLEN               = 64,
  parameter type readregflags_t             = logic,
  parameter type writeregflags_t            = logic,
  parameter type id_t                       = logic,
  parameter type hartid_t                   = logic,
  parameter type x_compressed_req_t         = logic,
  parameter type x_compressed_resp_t        = logic,
  parameter type x_issue_req_t              = logic,
  parameter type x_issue_resp_t             = logic,
  parameter type x_register_t               = logic,
  parameter type x_commit_t                 = logic,
  parameter type x_result_t                 = logic,
  parameter type cvxif_req_t                = logic,
  parameter type cvxif_resp_t               = logic,
  localparam type registers_t               = logic [NrRgprPorts-1:0][XLEN-1:0]
) (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  cvxif_req_t   cvxif_req_i,
  output cvxif_resp_t  cvxif_resp_o
);

  // Issue
  x_issue_req_t  issue_req;
  x_issue_resp_t issue_resp;
  logic          issue_valid;
  logic          issue_ready, issue_ready_id;

  // Registers
  x_register_t   register;
  logic          register_valid;

  // Decoded -> EX
  registers_t        registers;
  hash_pkg::opcode_t opcode;
  hartid_t           issue_hartid, hartid;
  id_t               issue_id, id;
  logic [4:0]        issue_rd, rd;
  logic [XLEN-1:0]   result;
  logic              we, ex_valid;

  // Busy gating - block new issues while a multi-cycle op runs
  logic ex_busy;

  assign issue_req      = cvxif_req_i.issue_req;
  assign issue_valid    = cvxif_req_i.issue_valid;
  assign register       = cvxif_req_i.register;
  assign register_valid = cvxif_req_i.register_valid;

  hash_xif_id #(
    .copro_issue_resp_t (hash_pkg::copro_issue_resp_t),
    .opcode_t           (hash_pkg::opcode_t),
    .NbInstr            (hash_pkg::NbInstr),
    .CoproInstr         (hash_pkg::CoproInstr),
    .NrRgprPorts        (NrRgprPorts),
    .hartid_t           (hartid_t),
    .id_t               (id_t),
    .x_issue_req_t      (x_issue_req_t),
    .x_issue_resp_t     (x_issue_resp_t),
    .x_register_t       (x_register_t),
    .registers_t        (registers_t)
  ) i_id (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .issue_valid_i    (issue_valid),
    .issue_req_i      (issue_req),
    .issue_ready_o    (issue_ready_id),
    .issue_resp_o     (issue_resp),
    .register_valid_i (register_valid),
    .register_i       (register),
    .registers_o      (registers),
    .opcode_o         (opcode),
    .hartid_o         (issue_hartid),
    .id_o             (issue_id),
    .rd_o             (issue_rd)
  );

  // When EX is busy, deassert issue_ready so CPU stalls the new op.
  assign issue_ready = issue_ready_id & ~ex_busy;

  hash_xif_ex #(
    .NrRgprPorts   (NrRgprPorts),
    .XLEN          (XLEN),
    .hartid_t      (hartid_t),
    .id_t          (id_t),
    .registers_t   (registers_t),
    .x_issue_req_t (x_issue_req_t)
  ) i_ex (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .issue_valid_i (issue_valid),
    .issue_ready_i (issue_ready),
    .registers_i   (registers),
    .opcode_i      (opcode),
    .hartid_i      (issue_hartid),
    .id_i          (issue_id),
    .rd_i          (issue_rd),
    .issue_req_i   (issue_req),
    .result_o      (result),
    .hartid_o      (hartid),
    .id_o          (id),
    .rd_o          (rd),
    .valid_o       (ex_valid),
    .we_o          (we)
  );

  // EX busy detection: a multi-cycle op is in flight whenever the FSM is
  // not in S_IDLE; expose it from the EX module via a small mirror here
  // (cheaper than threading a port for one bit).
  // The EX FSM transitions back to S_IDLE on the cycle that produces
  // ex_valid, so we deassert busy as soon as ex_valid pulses.
  logic busy_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) busy_q <= 1'b0;
    else begin
      if (ex_valid)                         busy_q <= 1'b0;
      else if (issue_valid && issue_ready)  busy_q <= 1'b1;
    end
  end
  assign ex_busy = busy_q;

  // Output cvxif response
  always_comb begin
    cvxif_resp_o.result_valid  = ex_valid;
    cvxif_resp_o.result.hartid = hartid;
    cvxif_resp_o.result.id     = id;
    cvxif_resp_o.result.data   = result;
    cvxif_resp_o.result.rd     = rd;
    cvxif_resp_o.result.we     = we;
    cvxif_resp_o.issue_ready   = issue_ready;
    cvxif_resp_o.issue_resp    = issue_resp;
    cvxif_resp_o.register_ready = issue_ready;
  end

  // Compressed-instruction predecoder (none accepted)
  x_compressed_req_t  compressed_req;
  x_compressed_resp_t compressed_resp;
  logic               compressed_valid, compressed_ready;

  assign compressed_req   = cvxif_req_i.compressed_req;
  assign compressed_valid = cvxif_req_i.compressed_valid;

  hash_xif_cid #(
    .copro_compressed_resp_t (hash_pkg::copro_compressed_resp_t),
    .NbInstr                 (hash_pkg::NbCompInstr),
    .CoproInstr              (hash_pkg::CoproCompInstr),
    .x_compressed_req_t      (x_compressed_req_t),
    .x_compressed_resp_t     (x_compressed_resp_t)
  ) i_cid (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .compressed_valid_i (compressed_valid),
    .compressed_req_i   (compressed_req),
    .compressed_ready_o (compressed_ready),
    .compressed_resp_o  (compressed_resp)
  );

  assign cvxif_resp_o.compressed_resp  = compressed_resp;
  assign cvxif_resp_o.compressed_ready = compressed_ready;

endmodule
