// Out-of-context synthesis top for kecc_aes_k_axi_top (area/timing check
// only -- no board pins, no bitstream). See ../README.md.
//
// kecc_aes_k_axi_top's axi_req_t/axi_rsp_t are `parameter type`, which
// Vivado's `-generic` cannot bind (generics are for value parameters only).
// This top binds them to ariane_axi_soc::req_slv_t/resp_slv_t -- the exact
// types corev_apu/tb/ariane_testharness.sv and
// corev_apu/fpga/src/ariane_xilinx.sv use to instantiate `i_loose_aes_slv`
// -- so the synthesized port widths match the real integration, not an
// idealized standalone width. AXI_ID_WIDTH/AXI_USER_WIDTH mirror the same
// two sites' actual parameter values (ariane_axi_soc::IdWidthSlave /
// ariane_axi_soc::UserWidth, which both derive from the same
// cva6_config_pkg the two production tops pick up via TARGET_CFG).
//
// SBOX_IMPL/PARALLEL_SLICES and which vN RTL directory got compiled (via
// `+define+KECC_AES_K_LOOSE_${AES_LOOSE_VERSION}`) are selected by
// run_synth.tcl's -generic and -tclargs, not by this file.

module kecc_aes_k_axi_synth_top #(
    parameter int unsigned SBOX_IMPL       = 0,
    parameter int unsigned PARALLEL_SLICES = 4
) (
    input  logic                       clk_i,
    input  logic                       rst_ni,
    input  logic                       test_mode_i,
    input  ariane_axi_soc::req_slv_t   axi_req_i,
    output ariane_axi_soc::resp_slv_t  axi_rsp_o,
    output logic                       kecc_aes_k_axi_intr_o
);

  // Instance hierarchy this flow's area reports key off of:
  //   i_kecc_aes_k_axi_top                          -- whole wrapper (AXI slave port to core)
  //   i_kecc_aes_k_axi_top/i_axi2reg                 -- axi_to_reg bridge alone
  //   i_kecc_aes_k_axi_top/kecc_aes_k_axi_reg_top_i  -- reggen register file alone (KECCAK_DATA[25] + KEY/BLOCK/RESULT/CTRL/STATUS)
  //   i_kecc_aes_k_axi_top/i_keccak_aes_k_top        -- keccak_aes_k_top core alone
  kecc_aes_k_axi_top #(
      .AXI_ADDR_WIDTH  (ariane_axi_soc::AddrWidth),
      .AXI_DATA_WIDTH  (ariane_axi_soc::DataWidth),
      .AXI_ID_WIDTH    (ariane_axi_soc::IdWidthSlave),
      .AXI_USER_WIDTH  (ariane_axi_soc::UserWidth),
      .SBOX_IMPL       (SBOX_IMPL),
      .PARALLEL_SLICES (PARALLEL_SLICES),
      .axi_req_t       (ariane_axi_soc::req_slv_t),
      .axi_rsp_t       (ariane_axi_soc::resp_slv_t)
  ) i_kecc_aes_k_axi_top (
      .clk_i               (clk_i),
      .rst_ni              (rst_ni),
      .test_mode_i         (test_mode_i),
      .axi_req_i           (axi_req_i),
      .axi_rsp_o           (axi_rsp_o),
      .kecc_aes_k_axi_intr_o(kecc_aes_k_axi_intr_o)
  );

endmodule
