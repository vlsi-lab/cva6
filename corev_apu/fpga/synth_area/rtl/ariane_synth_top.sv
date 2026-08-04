// Copyright 2026 Thales DIS France SAS
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
// You may obtain a copy of the License at https://solderpad.org/licenses/
//
// Description: Out-of-context synthesis top for the CVA6 core + kecc_aes_k_xif
//              coprocessor (area/timing check only -- no board pins, no
//              bitstream). See ../README.md.
//
// `ariane`'s own CVA6Cfg parameter defaults to config_pkg::cva6_cfg_empty,
// which has CvxifEn=0 -- the coprocessor would not be instantiated at all if
// left at that default. Binding CVA6Cfg here to
// build_config_pkg::build_config(cva6_config_pkg::cva6_cfg) -- the same
// idiom every other CVA6 top (ariane_xilinx.sv, ariane_testharness.sv, ...)
// uses -- picks up whichever cva6_config_pkg.sv was compiled into this run.
// For this flow that must be core/include/cv64a6_imac_crypto_config_pkg.sv
// (the only config in this repo with CoproType == COPRO_KECC_AES_K and
// CvxifEn == 1), selected by scripts/run_synth.tcl, not by this file.
//
// rvfi_probes_{instr,csr}_t must be computed from CVA6Cfg via the RVFI
// macros, not left at ariane's trivial `= logic` default: csr_regfile.sv
// unconditionally does `rvfi_csr_o.fcsr_q = ...` (and many more per-CSR
// field assignments) regardless of whether anything downstream reads
// rvfi_probes_o, so rvfi_csr_o's type must be the real packed struct or
// those field-selects don't exist and Vivado fails elaboration
// ("cannot resolve hierarchical name") even though rvfi_probes_o itself is
// left unconnected below -- this synthesis-only top still doesn't use the
// RVFI probes for anything, it just has to type them correctly to compile.

`include "rvfi_types.svh"

module ariane_synth_top #(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = build_config_pkg::build_config(cva6_config_pkg::cva6_cfg),
    localparam type rvfi_probes_instr_t = `RVFI_PROBES_INSTR_T(CVA6Cfg),
    localparam type rvfi_probes_csr_t = `RVFI_PROBES_CSR_T(CVA6Cfg),
    localparam type rvfi_probes_t = struct packed {
      rvfi_probes_csr_t   csr;
      rvfi_probes_instr_t instr;
    }
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic [CVA6Cfg.VLEN-1:0] boot_addr_i,
    input  logic [CVA6Cfg.XLEN-1:0] hart_id_i,
    input  logic [             1:0] irq_i,
    input  logic                    ipi_i,
    input  logic                    time_irq_i,
    input  logic                    debug_req_i,
    output ariane_axi::req_t        noc_req_o,
    input  ariane_axi::resp_t       noc_resp_i
);

  // Instance hierarchy this flow's area reports key off of:
  //   i_ariane/i_cva6                                                  -- CVA6 core alone
  //   i_ariane/gen_cvxif/gen_COPRO_KECC_AES_K/i_kecc_aes_k_xif_coprocessor -- coprocessor alone
  //   i_ariane (this whole module)                                     -- entire system
  ariane #(
      .CVA6Cfg(CVA6Cfg),
      .rvfi_probes_instr_t(rvfi_probes_instr_t),
      .rvfi_probes_csr_t(rvfi_probes_csr_t),
      .rvfi_probes_t(rvfi_probes_t)
  ) i_ariane (
      .clk_i        (clk_i),
      .rst_ni       (rst_ni),
      .boot_addr_i  (boot_addr_i),
      .hart_id_i    (hart_id_i),
      .irq_i        (irq_i),
      .ipi_i        (ipi_i),
      .time_irq_i   (time_irq_i),
      .debug_req_i  (debug_req_i),
      .rvfi_probes_o(),
      .noc_req_o    (noc_req_o),
      .noc_resp_i   (noc_resp_i)
  );

endmodule
