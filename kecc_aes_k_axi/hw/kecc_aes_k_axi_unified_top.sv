// kecc_aes_k_axi_unified (v2) Accelerator IP - Loosely, area-optimized
// Top module: AXI wrapper for keccak_aes_k_top_unified (unified AES/Keccak
// core with NO internal working-state register -- see
// kecc_aes_k_axi/hw/rtl/v2_unified/keccak_aes_k_top_unified.sv's header for
// the full rationale, and kecc_aes_k_axi/hw/regs/kecc_aes_k_axi_unified.hjson
// for the register map, which differs from kecc_aes_k_axi.hjson's: BLOCK0-1
// are hardware-writable (hwaccess: hrw, at 32-bit-word granularity) and
// there is no separate RESULT0-1 register -- software reads BLOCK0-1 as the
// AES result once STATUS.RESULT_VALID is 1.
//
// Unlike kecc_aes_k_axi_top.sv, this wrapper does the KECCAK_DATA0-24/
// BLOCK0-1 <-> core wiring as a direct, live, every-cycle connection
// (reg2hw.*.q straight into the core's *_i ports, core's *_o/*_we straight
// into hw2reg.*.d/.de) instead of load-once-write-once staging -- the
// register file's own flip-flops are the core's only working storage.
//
// Module name is deliberately still `kecc_aes_k_axi_top` (same as the
// non-unified wrapper, ../kecc_aes_k_axi_top.sv) -- core/Flist.cva6's
// AES_LOOSE_WRAPPER selects which one of these two FILES gets compiled in
// (mutually exclusive, same trick already used for keccak_aes_k_top across
// v2/v3/v4/v5), so corev_apu/tb/ariane_testharness.sv's/
// corev_apu/fpga/src/ariane_xilinx.sv's existing `kecc_aes_k_axi_top #(...)
// i_loose_aes_slv (...)` instantiation needs no SoC-level change at all to
// pick this design instead -- exactly the "should adapt easily" property
// requested for this redesign. SBOX_IMPL/PARALLEL_SLICES are accepted (and
// ignored) purely so that fixed instantiation's `.SBOX_IMPL(...)`/
// `.PARALLEL_SLICES(...)` connections still elaborate -- v2/v3's original
// kecc_aes_k_axi_top.sv already does the same for the same reason.

`include "register_interface/typedef.svh"
`include "register_interface/assign.svh"

module kecc_aes_k_axi_top #(
	parameter int unsigned AXI_ADDR_WIDTH = 64,
	parameter int unsigned AXI_DATA_WIDTH = 64,
	parameter int unsigned AXI_ID_WIDTH,
	parameter int unsigned AXI_USER_WIDTH,
	parameter int unsigned SBOX_IMPL       = 0,  // unused -- see header comment
	parameter int unsigned PARALLEL_SLICES = 4,  // unused -- see header comment
	parameter type axi_req_t = logic,
	parameter type axi_rsp_t = logic
)(
	input 	logic 		clk_i,
	input 	logic 		rst_ni,
	input	logic 		test_mode_i,

	input 	axi_req_t 	axi_req_i,
	output 	axi_rsp_t 	axi_rsp_o,

	output 	logic 		kecc_aes_k_axi_intr_o
);
	typedef logic [AXI_ADDR_WIDTH-1:0] addr_t;
	typedef logic [AXI_DATA_WIDTH-1:0] data_t;
	typedef logic [AXI_DATA_WIDTH/8-1:0] strb_t;
	`REG_BUS_TYPEDEF_REQ(reg_req_t, addr_t, data_t, strb_t);
	`REG_BUS_TYPEDEF_RSP(reg_rsp_t, data_t);

	kecc_aes_k_axi_unified_reg_pkg::kecc_aes_k_axi_unified_reg2hw_t reg_file_to_ip;
	kecc_aes_k_axi_unified_reg_pkg::kecc_aes_k_axi_unified_hw2reg_t ip_to_reg_file;
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

	kecc_aes_k_axi_unified_reg_top # (
		.reg_req_t(reg_req_t),
		.reg_rsp_t(reg_rsp_t)
	) kecc_aes_k_axi_unified_reg_top_i (
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.reg_req_i(reg_req_i),
		.reg_rsp_o(reg_rsp_o),
		.reg2hw(reg_file_to_ip),
		.hw2reg(ip_to_reg_file),
		.devmode_i(1'b1)
	);

	// keccak_aes_k_top_unified's init/next are single-cycle-pulse inputs, but
	// CTRL.INIT/CTRL.NEXT are software-owned, level-held bits -- same
	// edge-detect as the non-unified wrapper's identical CTRL.INIT/NEXT.
	logic ctrl_init_old, ctrl_next_old;
	logic core_init, core_next;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			ctrl_init_old <= 1'b0;
			ctrl_next_old <= 1'b0;
		end else begin
			ctrl_init_old <= reg_file_to_ip.ctrl.init.q;
			ctrl_next_old <= reg_file_to_ip.ctrl.next.q;
		end
	end
	assign core_init = reg_file_to_ip.ctrl.init.q & ~ctrl_init_old;
	assign core_next = reg_file_to_ip.ctrl.next.q & ~ctrl_next_old;

	// Core outputs.
	logic core_ready, core_result_valid, core_keccak_done;

	assign ip_to_reg_file.status.ready.d          = core_ready;
	assign ip_to_reg_file.status.ready.de         = 1'b1;
	assign ip_to_reg_file.status.result_valid.d   = core_result_valid;
	assign ip_to_reg_file.status.result_valid.de  = 1'b1;

	assign ip_to_reg_file.status.keccak_done.d  = 1'b1;
	assign ip_to_reg_file.status.keccak_done.de = core_keccak_done;

	// AES key: software-owned staging register, read directly by the core
	// every cycle -- unchanged from the non-unified wrapper (the key
	// SCHEDULE derived from it stays internal to the core either way, see
	// keccak_aes_k_top_unified.sv's header).
	logic [255:0] core_key;

	genvar gk;
	generate
		for (gk = 0; gk < 4; gk++) begin : g_key_word
			assign core_key[64*gk +: 64] = reg_file_to_ip.key[gk].q;
		end
	endgenerate

	// AES's round-by-round working register AND result -- live wiring both
	// ways, no staging. BLOCK0's two 32-bit fields are AES words 0/1
	// (bits [127:96]/[95:64]); BLOCK0's are words 2/3 (bits [63:32]/[31:0])
	// -- register NAME vs. which half it holds is intentionally swapped
	// from the naive reading, to match kecc_aes_k_axi_unified.c's/the
	// original driver's fixed BLOCK1-gets-the-upper-half convention. See
	// kecc_aes_k_axi_unified.hjson's BLOCK1 field comment for why.
	logic [127:0] core_aes_block_i, core_aes_block_o;
	logic         core_aes_block_w0_we, core_aes_block_w1_we,
	              core_aes_block_w2_we, core_aes_block_w3_we;

	assign core_aes_block_i = { reg_file_to_ip.block1.w0.q, reg_file_to_ip.block1.w1.q,
	                             reg_file_to_ip.block0.w2.q, reg_file_to_ip.block0.w3.q };

	assign ip_to_reg_file.block1.w0.d  = core_aes_block_o[127:96];
	assign ip_to_reg_file.block1.w0.de = core_aes_block_w0_we;
	assign ip_to_reg_file.block1.w1.d  = core_aes_block_o[95:64];
	assign ip_to_reg_file.block1.w1.de = core_aes_block_w1_we;
	assign ip_to_reg_file.block0.w2.d  = core_aes_block_o[63:32];
	assign ip_to_reg_file.block0.w2.de = core_aes_block_w2_we;
	assign ip_to_reg_file.block0.w3.d  = core_aes_block_o[31:0];
	assign ip_to_reg_file.block0.w3.de = core_aes_block_w3_we;

	// Keccak's full 1600-bit state -- live wiring both ways, no staging:
	// keccak_data[i].q feeds the core's keccak_state_i every cycle, and
	// keccak_state_o commits back into keccak_data[i].d every one of the
	// 24 rounds (keccak_state_we, one shared enable for all 25 words since
	// a round always updates the whole state at once).
	logic [1599:0] core_keccak_state_i, core_keccak_state_o;
	logic          core_keccak_state_we;

	genvar gw;
	generate
		for (gw = 0; gw < 25; gw++) begin : g_keccak_word
			assign core_keccak_state_i[64*gw +: 64]  = reg_file_to_ip.keccak_data[gw].q;
			assign ip_to_reg_file.keccak_data[gw].d  = core_keccak_state_o[64*gw +: 64];
			assign ip_to_reg_file.keccak_data[gw].de = core_keccak_state_we;
		end
	endgenerate

	// result_valid is level-held on the core, so it is edge-detected here
	// purely for the interrupt line -- same as the non-unified wrapper.
	logic core_result_valid_old, result_valid_rise;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			core_result_valid_old <= 1'b0;
		end else begin
			core_result_valid_old <= core_result_valid;
		end
	end
	assign result_valid_rise = core_result_valid & ~core_result_valid_old;

	assign kecc_aes_k_axi_intr_o = core_keccak_done | result_valid_rise;

	keccak_aes_k_top_unified i_keccak_aes_k_top_unified (
		.clk          (clk_i),
		.reset_n      (rst_ni),
		.zeroize      (reg_file_to_ip.ctrl.zeroize.q),

		.sel          (reg_file_to_ip.ctrl.sel.q),
		.encdec       (reg_file_to_ip.ctrl.encdec.q),
		.keylen       (reg_file_to_ip.ctrl.keylen.q),

		.init         (core_init),
		.next         (core_next),
		.ready        (core_ready),

		.key             (core_key),
		.aes_block_i     (core_aes_block_i),
		.aes_block_o     (core_aes_block_o),
		.aes_block_w0_we (core_aes_block_w0_we),
		.aes_block_w1_we (core_aes_block_w1_we),
		.aes_block_w2_we (core_aes_block_w2_we),
		.aes_block_w3_we (core_aes_block_w3_we),
		.result_valid    (core_result_valid),

		.keccak_state_i  (core_keccak_state_i),
		.keccak_state_o  (core_keccak_state_o),
		.keccak_state_we (core_keccak_state_we),
		.keccak_done     (core_keccak_done)
	);

endmodule
