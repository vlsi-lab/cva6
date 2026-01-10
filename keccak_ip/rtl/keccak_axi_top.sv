// Keccak Accelerator IP - Loosely
// Top module description for the AXI accellerator 
// Author: Federico Runco

`ifdef SYNTHESIS
	`include "./register_interface/typedef.svh"
	`include "./register_interface/assign.svh"
`else
	`include "/register_interface/typedef.svh"
	`include "/register_interface/assign.svh"
`endif

module keccak_axi_top 
	import pkg_keccak::*;
#(
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

	output 	logic 		keccak_intr_o
);
	typedef logic [AXI_ADDR_WIDTH-1:0] addr_t;
	typedef logic [AXI_DATA_WIDTH-1:0] data_t;
	typedef logic [AXI_DATA_WIDTH/8-1:0] strb_t;
	`REG_BUS_TYPEDEF_REQ(reg_req_t, addr_t, data_t, strb_t);
  	`REG_BUS_TYPEDEF_RSP(reg_rsp_t, data_t);

	keccak_reg_pkg::keccak_reg2hw_t reg_file_to_ip;
	keccak_reg_pkg::keccak_hw2reg_t ip_to_reg_file;
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


	logic[1599:0] keccak_din, keccak_dout;

	keccak_reg_top # (
		.reg_req_t(reg_req_t),
		.reg_rsp_t(reg_rsp_t)
	) keccak_reg_top_i (
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.reg_req_i(reg_req_i),
		.reg_rsp_o(reg_rsp_o),
		.reg2hw(reg_file_to_ip),
		.hw2reg(ip_to_reg_file),
		.devmode_i(1'b1)
	);

	// Keccak-F CU issues a single clock pulse to signal completion of the permutation,
	// to make it work during polling mode we need to latch the done signal until the start register bit is cleared
	logic csreg_start_old, keccak_start, keccak_done;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			csreg_start_old <= 1'b0;
		end else begin
			csreg_start_old <= reg_file_to_ip.csreg.start.q;
		end
	end
	assign keccak_start = reg_file_to_ip.csreg.start.q & ~csreg_start_old;
	assign ip_to_reg_file.csreg.done.d = keccak_done;
	assign ip_to_reg_file.csreg.done.de = keccak_done;

	keccak_f i_keccak (
		.clk(clk_i),
		.rst_n(rst_ni),
		.start_i(keccak_start),
		.Din(keccak_din),
		.Dout(keccak_dout),
		.status_d(keccak_done),
		.keccak_intr(keccak_intr_o)
	);

	assign keccak_din = reg_file_to_ip.data;

	genvar i;
	generate 
		for (i=0; i < 25; i++) begin 
			assign ip_to_reg_file.data[i].d = keccak_dout[(i+1)*64-1 -: 64];
			assign ip_to_reg_file.data[i].de = keccak_done;
		end
	endgenerate

endmodule