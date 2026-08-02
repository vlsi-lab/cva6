// Keccak Accelerator IP - Loosely
// Top module description for the AXI accellerator
// Author: Federico Runco
//
// Bulk register interface: CTRL (start/done) + 25 independent DATA[i]
// registers, one per 64-bit state word. The register file's own DATA
// multireg *is* the permutation engine's working storage -- keccak_dp holds
// no internal copy, it reads/drives these registers directly every round
// via state_i/state_o/state_we_o. So there is still exactly one 1600-bit
// storage location, while software gets a plain, dependency-free bulk
// interface (no indexed streaming, no per-word handshake).

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
	logic ctrl_start_old, keccak_start, keccak_done;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			ctrl_start_old <= 1'b0;
		end else begin
			ctrl_start_old <= reg_file_to_ip.ctrl.start.q;
		end
	end
	assign keccak_start = reg_file_to_ip.ctrl.start.q & ~ctrl_start_old;
	assign ip_to_reg_file.ctrl.done.d = keccak_done;
	assign ip_to_reg_file.ctrl.done.de = keccak_done;

	// START is software-owned only -- hardware never writes it back.
	assign ip_to_reg_file.ctrl.start.d = 1'b0;
	assign ip_to_reg_file.ctrl.start.de = 1'b0;

	// Pack/unpack between the register file's 25 independent DATA[i] words
	// and keccak_dp's k_state view, using the same w -> (y,x) = (w/5, w%5)
	// convention the old Dout flatten used.
	k_state state_i, state_o;
	logic state_we;

	genvar gw;
	generate
		for (gw = 0; gw < 25; gw++) begin : g_word
			assign state_i[gw/5][gw%5] = reg_file_to_ip.data[gw].q;
			assign ip_to_reg_file.data[gw].d  = state_o[gw/5][gw%5];
			assign ip_to_reg_file.data[gw].de = state_we;
		end
	endgenerate

	keccak_f i_keccak (
		.clk         (clk_i),
		.rst_n       (rst_ni),
		.start_i     (keccak_start),
		.state_i     (state_i),
		.state_o     (state_o),
		.state_we_o  (state_we),
		.status_d    (keccak_done),
		.keccak_intr (keccak_intr_o)
	);

endmodule
