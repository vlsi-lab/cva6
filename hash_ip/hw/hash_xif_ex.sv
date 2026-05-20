// Copyright 2025 PoliTO - EDGE Group, @VLSI Lab
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// HASH coprocessor XIF execution stage. Wraps the `hash` compute module and
// produces a registered cvxif result.
//
//   - Single-cycle ops (INIT, LOAD, KABSORB, STORE, KREAD3, CL_*) sample
//     hash_rd / opcode in the issue cycle and pulse result_valid one cycle
//     later (the result register is flopped on every clock).
//   - Multi-cycle ops (KSTART, KPERM, all THASH/PRF) latch context on issue,
//     stall issue_ready (via the busy logic in hash_xif), and pulse
//     result_valid when done_keccak_o / done_sphincs_o fires.

module hash_xif_ex
  import hash_pkg::*;
#(
  parameter int unsigned NrRgprPorts = 3,
  parameter int unsigned XLEN        = 64,
  parameter type hartid_t            = logic,
  parameter type id_t                = logic,
  parameter type registers_t         = logic,
  parameter type x_issue_req_t       = logic
) (
  input  logic                clk_i,
  input  logic                rst_ni,

  // From ID stage
  input  logic                issue_valid_i,
  input  logic                issue_ready_i,
  input  registers_t          registers_i,
  input  hash_pkg::opcode_t   opcode_i,
  input  hartid_t             hartid_i,
  input  id_t                 id_i,
  input  logic [4:0]          rd_i,
  input  x_issue_req_t        issue_req_i,

  // To CVA6 cvxif result interface
  output logic [XLEN-1:0]     result_o,
  output hartid_t             hartid_o,
  output id_t                 id_o,
  output logic [4:0]          rd_o,
  output logic                valid_o,
  output logic                we_o
);

  // --------------------------------------------------------------------------
  // Op classification
  // --------------------------------------------------------------------------
  function automatic logic is_keccak_op (hash_pkg::opcode_t op);
    return (op == OP_KSTART) || (op == OP_KPERM);
  endfunction

  function automatic logic is_sphincs_op (hash_pkg::opcode_t op);
    return (op == OP_THASH1)     || (op == OP_THASH2)     || (op == OP_PRF_ADDR) ||
           (op == OP_THASH1_192) || (op == OP_THASH2_192) || (op == OP_PRF_192)  ||
           (op == OP_THASH1_256) || (op == OP_THASH2_256) || (op == OP_PRF_256);
  endfunction

  function automatic logic op_writes_rd (hash_pkg::opcode_t op);
    return (op == OP_STORE) || (op == OP_KREAD3);
  endfunction

  // --------------------------------------------------------------------------
  // FSM state
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    S_IDLE      = 2'b00,
    S_WAIT_KECC = 2'b01,
    S_WAIT_SPHX = 2'b10
  } state_e;

  state_e   state_q, state_d;
  hartid_t  hartid_q;
  id_t      id_q;
  logic [4:0] rd_q;
  logic       we_q;

  logic     issue_accept;
  assign    issue_accept = issue_valid_i & issue_ready_i;

  // --------------------------------------------------------------------------
  // hash core (combinational rd_o; FSM-internal completion pulses)
  // --------------------------------------------------------------------------
  logic              hash_start;
  logic [XLEN-1:0]   hash_rd;
  logic              done_keccak, done_sphincs;
  hash_pkg::opcode_t insn_to_hash;

  // Drive the live opcode only on the issue cycle so register-file writes
  // happen exactly once per issued instruction.
  assign insn_to_hash = issue_accept ? opcode_i : OP_NONE;
  assign hash_start   = issue_accept &&
                        (opcode_i == OP_KSTART || opcode_i == OP_KPERM);

  hash i_hash (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .insn_i         (insn_to_hash),
    .rs1_i          (registers_i[0]),
    .rs2_i          (registers_i[1]),
    .rs3_i          (registers_i[2]),
    .start_i        (hash_start),
    .done_keccak_o  (done_keccak),
    .done_sphincs_o (done_sphincs),
    .rd_o           (hash_rd)
  );

  // --------------------------------------------------------------------------
  // FSM transitions + context latch
  // --------------------------------------------------------------------------
  always_comb begin
    state_d = state_q;
    case (state_q)
      S_IDLE: begin
        if (issue_accept) begin
          if      (is_keccak_op(opcode_i))  state_d = S_WAIT_KECC;
          else if (is_sphincs_op(opcode_i)) state_d = S_WAIT_SPHX;
        end
      end
      S_WAIT_KECC: if (done_keccak)  state_d = S_IDLE;
      S_WAIT_SPHX: if (done_sphincs) state_d = S_IDLE;
      default:     state_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q  <= S_IDLE;
      hartid_q <= '0;
      id_q     <= '0;
      rd_q     <= '0;
      we_q     <= 1'b0;
    end else begin
      state_q <= state_d;
      if (state_q == S_IDLE && issue_accept) begin
        hartid_q <= hartid_i;
        id_q     <= id_i;
        rd_q     <= rd_i;
        we_q     <= op_writes_rd(opcode_i);
      end
    end
  end

  // --------------------------------------------------------------------------
  // Result generation - registered cvxif outputs
  // --------------------------------------------------------------------------
  logic            valid_n, we_n;
  logic [XLEN-1:0] result_n;
  hartid_t         hartid_n;
  id_t             id_n;
  logic [4:0]      rd_n;

  always_comb begin
    valid_n  = 1'b0;
    result_n = '0;
    we_n     = 1'b0;
    hartid_n = hartid_q;
    id_n     = id_q;
    rd_n     = rd_q;

    if (state_q == S_IDLE && issue_accept &&
        !is_keccak_op(opcode_i) && !is_sphincs_op(opcode_i)) begin
      // Single-cycle op completes "next clock"
      valid_n  = 1'b1;
      result_n = hash_rd;            // sampled now while registers_i is valid
      we_n     = op_writes_rd(opcode_i);
      hartid_n = hartid_i;
      id_n     = id_i;
      rd_n     = rd_i;
    end else if (state_q == S_WAIT_KECC && done_keccak) begin
      valid_n  = 1'b1;
      result_n = '0;
      we_n     = we_q;               // 0 for KSTART/KPERM
    end else if (state_q == S_WAIT_SPHX && done_sphincs) begin
      valid_n  = 1'b1;
      result_n = '0;
      we_n     = we_q;               // 0 for THASH/PRF
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      result_o <= '0;
      hartid_o <= '0;
      id_o     <= '0;
      rd_o     <= '0;
      valid_o  <= 1'b0;
      we_o     <= 1'b0;
    end else begin
      valid_o  <= valid_n;
      result_o <= result_n;
      hartid_o <= hartid_n;
      id_o     <= id_n;
      rd_o     <= rd_n;
      we_o     <= we_n;
    end
  end

endmodule
