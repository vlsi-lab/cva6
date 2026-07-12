// Ascon Accelerator IP - Loosely
// Top module: wraps the Ascon permutation core as a loosely-coupled AXI4
// slave, mirroring keccak_ip/rtl/keccak_axi_top.sv: an axi_to_reg bridge
// feeds the lowRISC-reggen register file (ascon_reg_top), whose reg2hw/hw2reg
// structs drive/observe the Ascon permutation core.

`ifdef SYNTHESIS
  `include "./register_interface/typedef.svh"
  `include "./register_interface/assign.svh"
`else
  `include "/register_interface/typedef.svh"
  `include "/register_interface/assign.svh"
`endif

module ascon_axi_top
  import ascon_pkg::*;
#(
    parameter int unsigned AXI_ADDR_WIDTH = 64,
    parameter int unsigned AXI_DATA_WIDTH = 64,
    parameter int unsigned AXI_ID_WIDTH,
    parameter int unsigned AXI_USER_WIDTH,
    parameter type axi_req_t = logic,
    parameter type axi_rsp_t = logic
) (
    input  logic     clk_i,
    input  logic     rst_ni,
    input  logic     test_mode_i,
    input  axi_req_t axi_req_i,
    output axi_rsp_t axi_rsp_o,
    output logic     ascon_intr_o
);
  typedef logic [AXI_ADDR_WIDTH-1:0] addr_t;
  typedef logic [AXI_DATA_WIDTH-1:0] data_t;
  typedef logic [AXI_DATA_WIDTH/8-1:0] strb_t;
  `REG_BUS_TYPEDEF_REQ(reg_req_t, addr_t, data_t, strb_t);
  `REG_BUS_TYPEDEF_RSP(reg_rsp_t, data_t);

  ascon_reg_pkg::ascon_reg2hw_t reg_file_to_ip;
  ascon_reg_pkg::ascon_hw2reg_t ip_to_reg_file;
  reg_req_t reg_req_i;
  reg_rsp_t reg_rsp_o;

  axi_to_reg #(
      .ADDR_WIDTH(AXI_ADDR_WIDTH),
      .DATA_WIDTH(AXI_DATA_WIDTH),
      .ID_WIDTH  (AXI_ID_WIDTH),
      .USER_WIDTH(AXI_USER_WIDTH),
      .DECOUPLE_W(0),
      .axi_req_t (axi_req_t),
      .axi_rsp_t (axi_rsp_t),
      .reg_req_t (reg_req_t),
      .reg_rsp_t (reg_rsp_t)
  ) i_axi2reg (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .testmode_i(test_mode_i),
      .axi_req_i (axi_req_i),
      .axi_rsp_o (axi_rsp_o),
      .reg_req_o (reg_req_i),
      .reg_rsp_i (reg_rsp_o)
  );

  logic [STATE_WIDTH-1:0] ascon_din, ascon_dout;

  ascon_reg_top #(
      .reg_req_t(reg_req_t),
      .reg_rsp_t(reg_rsp_t)
  ) i_ascon_reg_top (
      .clk_i    (clk_i),
      .rst_ni   (rst_ni),
      .reg_req_i(reg_req_i),
      .reg_rsp_o(reg_rsp_o),
      .reg2hw   (reg_file_to_ip),
      .hw2reg   (ip_to_reg_file),
      .devmode_i(1'b1)
  );

  // ascon_top issues a single clock pulse to signal completion of the
  // permutation; to make this work under polling we latch the done signal
  // until the start register bit is cleared, and edge-detect the start bit
  // to generate a single-cycle start pulse (same trick as keccak_axi_top.sv).
  logic csreg_start_old, ascon_start, ascon_done;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      csreg_start_old <= 1'b0;
    end else begin
      csreg_start_old <= reg_file_to_ip.csreg.start.q;
    end
  end
  assign ascon_start = reg_file_to_ip.csreg.start.q & ~csreg_start_old;
  assign ip_to_reg_file.csreg.done.d  = ascon_done;
  assign ip_to_reg_file.csreg.done.de = ascon_done;
  assign ascon_intr_o = ascon_done;

  ascon_top i_ascon (
      .clk_i           (clk_i),
      .rst_ni          (rst_ni),
      .start_i         (ascon_start),
      .din_i           (ascon_din),
      .number_rounds_i (reg_file_to_ip.csreg.rounds.q),
      .dout_o          (ascon_dout),
      .done_o          (ascon_done)
  );

  assign ascon_din = reg_file_to_ip.data;

  genvar i;
  generate
    for (i = 0; i < NUM_LANE; i++) begin : gen_data_readback
      assign ip_to_reg_file.data[i].d  = ascon_dout[(i+1)*LANE_WIDTH-1 -: LANE_WIDTH];
      assign ip_to_reg_file.data[i].de = ascon_done;
    end
  endgenerate

endmodule
