// Copyright 2026 PoliTO - EDGE Group, @VLSI Lab
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Synthesis wrapper for stand-alone (out-of-context) synthesis of the
// HASH_IP coprocessor (`hash_xif`).
//
// `hash_xif` is fully parametric on the CV-X-IF struct types: synthesizing
// it directly would leave them at their default `logic` type and produce a
// degenerate 1-bit design. This wrapper instantiates the macros from
// `cvxif_types.svh` against a concrete CVA6 configuration (defaulting to
// `cva6_config_pkg::cva6_cfg`, normally `cv64a6_imafdc_sv39`) so the
// coprocessor is elaborated with the exact same types it sees inside the
// full SoC.
//
// Top of this module is the same as `hash_xif` itself, just with concrete
// struct ports instead of generic parameters.

`include "cvxif_types.svh"

module hash_xif_synth_top #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = build_config_pkg::build_config(cva6_config_pkg::cva6_cfg),
  // CV-X-IF concrete types (mirror corev_apu/src/ariane.sv)
  localparam type readregflags_t      = `READREGFLAGS_T(CVA6Cfg),
  localparam type writeregflags_t     = `WRITEREGFLAGS_T(CVA6Cfg),
  localparam type id_t                = `ID_T(CVA6Cfg),
  localparam type hartid_t            = `HARTID_T(CVA6Cfg),
  localparam type x_compressed_req_t  = `X_COMPRESSED_REQ_T(CVA6Cfg, hartid_t),
  localparam type x_compressed_resp_t = `X_COMPRESSED_RESP_T(CVA6Cfg),
  localparam type x_issue_req_t       = `X_ISSUE_REQ_T(CVA6Cfg, hartid_t, id_t),
  localparam type x_issue_resp_t      = `X_ISSUE_RESP_T(CVA6Cfg, writeregflags_t, readregflags_t),
  localparam type x_register_t        = `X_REGISTER_T(CVA6Cfg, hartid_t, id_t, readregflags_t),
  localparam type x_commit_t          = `X_COMMIT_T(CVA6Cfg, hartid_t, id_t),
  localparam type x_result_t          = `X_RESULT_T(CVA6Cfg, hartid_t, id_t, writeregflags_t),
  localparam type cvxif_req_t         = `CVXIF_REQ_T(CVA6Cfg, x_compressed_req_t, x_issue_req_t, x_register_t, x_commit_t),
  localparam type cvxif_resp_t        = `CVXIF_RESP_T(CVA6Cfg, x_compressed_resp_t, x_issue_resp_t, x_result_t)
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  cvxif_req_t  cvxif_req_i,
  output cvxif_resp_t cvxif_resp_o
);

  hash_xif #(
    .NrRgprPorts         (CVA6Cfg.NrRgprPorts),
    .XLEN                (CVA6Cfg.XLEN),
    .readregflags_t      (readregflags_t),
    .writeregflags_t     (writeregflags_t),
    .id_t                (id_t),
    .hartid_t            (hartid_t),
    .x_compressed_req_t  (x_compressed_req_t),
    .x_compressed_resp_t (x_compressed_resp_t),
    .x_issue_req_t       (x_issue_req_t),
    .x_issue_resp_t      (x_issue_resp_t),
    .x_register_t        (x_register_t),
    .x_commit_t          (x_commit_t),
    .x_result_t          (x_result_t),
    .cvxif_req_t         (cvxif_req_t),
    .cvxif_resp_t        (cvxif_resp_t)
  ) i_hash_xif (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .cvxif_req_i  (cvxif_req_i),
    .cvxif_resp_o (cvxif_resp_o)
  );

endmodule
