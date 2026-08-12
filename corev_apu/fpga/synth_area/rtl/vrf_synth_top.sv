// Description: Out-of-context synthesis top for the CVA6 core + vrf_ip
//              accelerator (area/timing check only -- no board pins, no
//              bitstream). See ../../../../IMPLEMENTATION.md.
//
// `ariane` and `vrf_axi_top` are instantiated as two independent sibling
// instances, each exposed directly via plain top-level ports, rather than
// wired together through a real SoC crossbar. This is deliberate: vrf_ip
// is an AXI-attached MMIO peripheral (unlike a CVXIF-tightly-coupled
// design), and building a functionally-correct interconnect between them
// is unnecessary for an area/utilization check -- Vivado's out-of-context
// synthesis reports each instance's internal logic area independently of
// what (if anything) drives its top-level ports, so a real xbar buys
// nothing here. Note also that `corev_apu/fpga/src/ariane_xilinx.sv` (the
// real FPGA top for other boards) never wires vrf_axi_top's DMA master
// port (dma_req_o/etc.) to anything at all -- only the simulation
// testbench (corev_apu/tb/ariane_testharness.sv) wires it correctly,
// through a separate axi_adapter instance. This wrapper exposes that port
// directly as plain top-level signals instead, which is sufficient here
// for the same reason: only the instance's own internal area matters.
//
// `ariane`'s own CVA6Cfg parameter defaults to config_pkg::cva6_cfg_empty;
// binding it here to build_config_pkg::build_config(cva6_config_pkg::cva6_cfg)
// -- the same idiom every other CVA6 top (ariane_xilinx.sv,
// ariane_testharness.sv, ...) uses -- picks up whichever cva6_config_pkg.sv
// was compiled into this run. For this flow that must be
// core/include/cv64a6_imac_crypto_config_pkg.sv, the config this whole
// project's RTL simulation work uses throughout, selected by
// scripts/run_synth.tcl via ${TARGET_CFG}, not by this file.
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

module vrf_synth_top #(
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
    input  ariane_axi::resp_t       noc_resp_i,

    // vrf_axi_top's slave port (accepts CPU MMIO commands) -- see header
    // comment for why this is not wired to noc_req_o/noc_resp_i above.
    input  ariane_axi::req_t        vrf_axi_req_i,
    output ariane_axi::resp_t       vrf_axi_rsp_o,
    output logic                    vrf_intr_o,

    // vrf_axi_top's own DMA master port toward DRAM (simple
    // single-outstanding req/gnt/valid interface; a real system wraps
    // this one level up with axi_adapter -- see header comment).
    output logic                    vrf_dma_req_o,
    output logic [ariane_axi::AddrWidth-1:0] vrf_dma_addr_o,
    output logic                    vrf_dma_we_o,
    output logic [ariane_axi::DataWidth-1:0] vrf_dma_wdata_o,
    output logic [ariane_axi::StrbWidth-1:0] vrf_dma_be_o,
    input  logic                    vrf_dma_gnt_i,
    input  logic                    vrf_dma_valid_i,
    input  logic [ariane_axi::DataWidth-1:0] vrf_dma_rdata_i
);

  // Instance hierarchy this flow's area reports key off of:
  //   i_ariane                -- CVA6 core + debug/CLINT-free SoC wrapper
  //   i_vrf_axi_top            -- entire vrf_ip accelerator (all 6 job
  //                               front-ends + shared Keccak core + reg file)
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

  vrf_axi_top #(
      .AXI_ADDR_WIDTH(ariane_axi::AddrWidth),
      .AXI_DATA_WIDTH(ariane_axi::DataWidth),
      .AXI_ID_WIDTH  (ariane_axi::IdWidth),
      .AXI_USER_WIDTH(ariane_axi::UserWidth),
      .axi_req_t     (ariane_axi::req_t),
      .axi_rsp_t     (ariane_axi::resp_t)
  ) i_vrf_axi_top (
      .clk_i       (clk_i),
      .rst_ni      (rst_ni),
      .test_mode_i (1'b0),
      .axi_req_i   (vrf_axi_req_i),
      .axi_rsp_o   (vrf_axi_rsp_o),
      .vrf_intr_o  (vrf_intr_o),
      .dma_req_o   (vrf_dma_req_o),
      .dma_addr_o  (vrf_dma_addr_o),
      .dma_we_o    (vrf_dma_we_o),
      .dma_wdata_o (vrf_dma_wdata_o),
      .dma_be_o    (vrf_dma_be_o),
      .dma_gnt_i   (vrf_dma_gnt_i),
      .dma_valid_i (vrf_dma_valid_i),
      .dma_rdata_i (vrf_dma_rdata_i)
  );

endmodule