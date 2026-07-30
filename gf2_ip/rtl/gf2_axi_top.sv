// GF(2) multiply-reduce Accelerator IP
// Top module for the AXI accelerator -- mirrors keccak_ip/rtl/keccak_axi_top.sv's
// structure (axi_to_reg -> gf2_reg_top -> datapath), same edge-detect pulse
// pattern for CTRL.NEXT as keccak_axi_top.sv/aes_axi_top.sv use.
//
// Wraps two gf2_mul_core instances (ACC_WIDTH=128/384, ported verbatim from
// cwrash/rtl/gf2_mul_core.v), selected by CTRL.MODE384 -- same structure as
// cwrash/rtl/gf2_mmio.v's gf2_mul_core_128/gf2_mul_core_384.
//
// Word packing (see gf2.hjson): each 64-bit register holds exactly one
// bf128_t/bf384_t limb (word 0 = low limb) -- a direct mapping of fields.c's
// BF_VALUE()/BF384_WORD() accessors, no byte-swapping needed (there's no
// legacy core to match byte order with, unlike AES).

`ifdef SYNTHESIS
	`include "./register_interface/typedef.svh"
	`include "./register_interface/assign.svh"
`else
	`include "/register_interface/typedef.svh"
	`include "/register_interface/assign.svh"
`endif

module gf2_axi_top #(
	parameter int unsigned AXI_ADDR_WIDTH = 64,
	parameter int unsigned AXI_DATA_WIDTH = 64,
	parameter int unsigned AXI_ID_WIDTH,
	parameter int unsigned AXI_USER_WIDTH,
	parameter type axi_req_t = logic,
	parameter type axi_rsp_t = logic
)(
	input 	logic 		clk_i,
	input 	logic 		rst_ni,
	input	logic 		test_mode_i,

	input 	axi_req_t 	axi_req_i,
	output 	axi_rsp_t 	axi_rsp_o,

	output 	logic 		gf2_intr_o
);
	typedef logic [AXI_ADDR_WIDTH-1:0] addr_t;
	typedef logic [AXI_DATA_WIDTH-1:0] data_t;
	typedef logic [AXI_DATA_WIDTH/8-1:0] strb_t;
	`REG_BUS_TYPEDEF_REQ(reg_req_t, addr_t, data_t, strb_t);
	`REG_BUS_TYPEDEF_RSP(reg_rsp_t, data_t);

	gf2_reg_pkg::gf2_reg2hw_t reg_file_to_ip;
	gf2_reg_pkg::gf2_hw2reg_t ip_to_reg_file;
	reg_req_t reg_req_i;
	reg_rsp_t reg_rsp_o;

	axi_to_reg #(
		.ADDR_WIDTH(AXI_ADDR_WIDTH),
		.DATA_WIDTH(AXI_DATA_WIDTH),
		.ID_WIDTH(AXI_ID_WIDTH),
		.USER_WIDTH(AXI_USER_WIDTH),
		.DECOUPLE_W(0),
		.axi_req_t(axi_req_t),
		.axi_rsp_t(axi_rsp_t),
		.reg_req_t(reg_req_t),
		.reg_rsp_t(reg_rsp_t)
	) i_axi2reg (
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.testmode_i(test_mode_i),
		.axi_req_i(axi_req_i),
		.axi_rsp_o(axi_rsp_o),
		.reg_req_o(reg_req_i),
		.reg_rsp_i(reg_rsp_o)
	);

	gf2_reg_top # (
		.reg_req_t(reg_req_t),
		.reg_rsp_t(reg_rsp_t)
	) gf2_reg_top_i (
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.reg_req_i(reg_req_i),
		.reg_rsp_o(reg_rsp_o),
		.reg2hw(reg_file_to_ip),
		.hw2reg(ip_to_reg_file),
		.devmode_i(1'b1)
	);

	// one-cycle NEXT pulse, gated by MODE384 to select which core sees it --
	// same edge-detect trick as keccak_axi_top.sv/aes_axi_top.sv
	logic next_old;
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) next_old <= 1'b0;
		else         next_old <= reg_file_to_ip.ctrl.next.q;
	end
	wire next_pulse = reg_file_to_ip.ctrl.next.q & ~next_old;
	wire mode384    = reg_file_to_ip.ctrl.mode384.q;

	wire [127:0] rhs_128 = { reg_file_to_ip.rhs[1].q, reg_file_to_ip.rhs[0].q };

	wire        ready128, ready384;
	wire        valid128, valid384;
	wire [127:0] result128;
	wire [383:0] result384;

	gf2_mul_core #(
		.ACC_WIDTH (128),
		.MODULUS   (384'h87)          //  bf128_modulus, fields.c
	) gf2_mul_core_128 (
		.clk          (clk_i),
		.reset_n      (rst_ni),
		.next         (next_pulse & ~mode384),
		.ready        (ready128),
		.lhs          ({ reg_file_to_ip.lhs128[1].q, reg_file_to_ip.lhs128[0].q }),
		.rhs          (rhs_128),
		.result       (result128),
		.result_valid (valid128)
	);

	gf2_mul_core #(
		.ACC_WIDTH (384),
		.MODULUS   (384'h100D)        //  bf384_modulus, fields.c
	) gf2_mul_core_384 (
		.clk          (clk_i),
		.reset_n      (rst_ni),
		.next         (next_pulse & mode384),
		.ready        (ready384),
		.lhs          ({ reg_file_to_ip.lhs384[5].q, reg_file_to_ip.lhs384[4].q,
		                  reg_file_to_ip.lhs384[3].q, reg_file_to_ip.lhs384[2].q,
		                  reg_file_to_ip.lhs384[1].q, reg_file_to_ip.lhs384[0].q }),
		.rhs          (rhs_128),
		.result       (result384),
		.result_valid (valid384)
	);

	wire core_ready = mode384 ? ready384 : ready128;
	wire core_valid = mode384 ? valid384 : valid128;
	logic core_valid_d;
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) core_valid_d <= 1'b0;
		else         core_valid_d <= core_valid;
	end

	always_comb begin
		ip_to_reg_file.res128[0].d  = result128[63:0];
		ip_to_reg_file.res128[0].de = valid128;
		ip_to_reg_file.res128[1].d  = result128[127:64];
		ip_to_reg_file.res128[1].de = valid128;

		ip_to_reg_file.res384[0].d  = result384[63:0];
		ip_to_reg_file.res384[0].de = valid384;
		ip_to_reg_file.res384[1].d  = result384[127:64];
		ip_to_reg_file.res384[1].de = valid384;
		ip_to_reg_file.res384[2].d  = result384[191:128];
		ip_to_reg_file.res384[2].de = valid384;
		ip_to_reg_file.res384[3].d  = result384[255:192];
		ip_to_reg_file.res384[3].de = valid384;
		ip_to_reg_file.res384[4].d  = result384[319:256];
		ip_to_reg_file.res384[4].de = valid384;
		ip_to_reg_file.res384[5].d  = result384[383:320];
		ip_to_reg_file.res384[5].de = valid384;

		ip_to_reg_file.status.ready.d  = core_ready;
		ip_to_reg_file.status.ready.de = 1'b1;
		ip_to_reg_file.status.valid.d  = core_valid;
		ip_to_reg_file.status.valid.de = 1'b1;
	end

	assign gf2_intr_o = core_valid && !core_valid_d;

endmodule
