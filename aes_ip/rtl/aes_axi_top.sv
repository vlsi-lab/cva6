// AES-128 forward-encrypt-only Accelerator IP
// Top module for the AXI accelerator -- mirrors keccak_ip/rtl/keccak_axi_top.sv's
// structure exactly (axi_to_reg -> aes_reg_top -> datapath), same edge-detect
// pulse pattern for CTRL bits since reggen's register file holds sw-written
// bits at a level (sw sets, sw clears) rather than self-clearing.
//
// Wraps aes_enc128_core (ported verbatim from cwrash/rtl/ -- AES-128
// forward-encrypt-only, no decrypt/192/256, see that file's header).
//
// Word packing (see aes.hjson): each 128-bit KEY/BLOCK/RESULT value is two
// 64-bit registers, word 0 = bytes[0:7] big-endian (MSB-first), word 1 =
// bytes[8:15] big-endian -- i.e. the 128-bit value read MSB-to-LSB is simply
// the 16-byte array in original order, matching aes_enc128_core's own
// expected [127:0] convention (same one aes_mmio.v / cwrash's pug_rv32
// wrapper already uses) with no extra byte-swapping needed at the word
// boundary.

`ifdef SYNTHESIS
	`include "./register_interface/typedef.svh"
	`include "./register_interface/assign.svh"
`else
	`include "/register_interface/typedef.svh"
	`include "/register_interface/assign.svh"
`endif

module aes_axi_top #(
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

	output 	logic 		aes_intr_o
);
	typedef logic [AXI_ADDR_WIDTH-1:0] addr_t;
	typedef logic [AXI_DATA_WIDTH-1:0] data_t;
	typedef logic [AXI_DATA_WIDTH/8-1:0] strb_t;
	`REG_BUS_TYPEDEF_REQ(reg_req_t, addr_t, data_t, strb_t);
	`REG_BUS_TYPEDEF_RSP(reg_rsp_t, data_t);

	aes_reg_pkg::aes_reg2hw_t reg_file_to_ip;
	aes_reg_pkg::aes_hw2reg_t ip_to_reg_file;
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

	aes_reg_top # (
		.reg_req_t(reg_req_t),
		.reg_rsp_t(reg_rsp_t)
	) aes_reg_top_i (
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.reg_req_i(reg_req_i),
		.reg_rsp_o(reg_rsp_o),
		.reg2hw(reg_file_to_ip),
		.hw2reg(ip_to_reg_file),
		.devmode_i(1'b1)
	);

	// === one-cycle pulse generation for INIT/NEXT -- same edge-detect
	//     trick keccak_axi_top.sv uses for CSREG.START, since the reg file
	//     holds sw-written bits at a level (sw sets, then explicitly
	//     clears) rather than self-clearing like cwrash's pug_rv32 wrapper.
	logic init_old, next_old, aes_init, aes_next;
	logic ctr_inc_pending;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			init_old <= 1'b0;
			next_old <= 1'b0;
		end else begin
			init_old <= reg_file_to_ip.ctrl.init.q;
			next_old <= reg_file_to_ip.ctrl.next.q;
		end
	end
	assign aes_init = reg_file_to_ip.ctrl.init.q & ~init_old;
	assign aes_next = reg_file_to_ip.ctrl.next.q & ~next_old;

	wire        core_ready;
	wire        core_valid;
	wire [127:0] core_result;
	wire [127:0] core_key   = { reg_file_to_ip.key[0].q,   reg_file_to_ip.key[1].q };
	wire [127:0] core_block = { reg_file_to_ip.block[0].q, reg_file_to_ip.block[1].q };

	aes_enc128_core aes_enc128_core_0 (
		.clk          (clk_i),
		.reset_n      (rst_ni),
		.init         (aes_init),
		.next         (aes_next),
		.ready        (core_ready),
		.key          (core_key),
		.block        (core_block),
		.result       (core_result),
		.result_valid (core_valid)
	);

	// === CTR_INC: latch at the next+ctr_inc write, apply the byte-reversed
	//     32-bit increment (matches aes_increment_iv()'s little-endian
	//     semantics against BLOCK[0]'s big-endian bytes[0:3] -- same logic
	//     as cwrash/rtl/aes_mmio.v's block0_rev/_inc, just operating on the
	//     top 32 bits of a 64-bit register here instead of a whole 32-bit one)
	//     on the completion edge.
	logic core_valid_d;
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			core_valid_d    <= 1'b0;
			ctr_inc_pending <= 1'b0;
		end else begin
			core_valid_d <= core_valid;
			if (aes_next && reg_file_to_ip.ctrl.ctr_inc.q) ctr_inc_pending <= 1'b1;
			else if (core_valid && !core_valid_d) ctr_inc_pending <= 1'b0;
		end
	end

	wire [31:0] block0_hi32     = reg_file_to_ip.block[0].q[63:32];   // bytes[0:3], MSB-first
	wire [31:0] block0_hi32_rev = { block0_hi32[7:0], block0_hi32[15:8],
	                                 block0_hi32[23:16], block0_hi32[31:24] };
	wire [31:0] block0_hi32_rev_inc = block0_hi32_rev + 32'd1;
	wire [31:0] block0_hi32_inc = { block0_hi32_rev_inc[7:0], block0_hi32_rev_inc[15:8],
	                                 block0_hi32_rev_inc[23:16], block0_hi32_rev_inc[31:24] };
	wire [63:0] block0_inc = { block0_hi32_inc, reg_file_to_ip.block[0].q[31:0] };

	always_comb begin
		ip_to_reg_file.block[0].d  = block0_inc;
		ip_to_reg_file.block[0].de = core_valid && !core_valid_d && ctr_inc_pending;
		ip_to_reg_file.block[1].d  = reg_file_to_ip.block[1].q;
		ip_to_reg_file.block[1].de = 1'b0;

		ip_to_reg_file.result[0].d  = core_result[127:64];
		ip_to_reg_file.result[0].de = core_valid;
		ip_to_reg_file.result[1].d  = core_result[63:0];
		ip_to_reg_file.result[1].de = core_valid;

		ip_to_reg_file.status.ready.d  = core_ready;
		ip_to_reg_file.status.ready.de = 1'b1;
		ip_to_reg_file.status.valid.d  = core_valid;
		ip_to_reg_file.status.valid.de = 1'b1;
	end

	assign aes_intr_o = core_valid && !core_valid_d;

endmodule
