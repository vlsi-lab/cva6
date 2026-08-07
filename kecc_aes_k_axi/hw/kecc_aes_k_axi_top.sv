// kecc_aes_k_axi (v2) Accelerator IP - Loosely
// Top module: AXI wrapper for keccak_aes_k_top (unified AES/Keccak core)
//
// Bulk register interface: CTRL (zeroize/sel/encdec/keylen/init/next) +
// STATUS (ready/result_valid/keccak_done) + KEY[0:3]/BLOCK[0:1] (software
// staging) + RESULT[0:1] (hardware-driven) + 25 independent KECCAK_DATA[i]
// registers, one per 64-bit Keccak state word. The register file's own
// KECCAK_DATA multireg *is* keccak_aes_k_top's working storage for the
// Keccak path (state_reg) -- see kecc_aes_k_axi.hjson's header comment for
// the full derivation.

`include "register_interface/typedef.svh"
`include "register_interface/assign.svh"

module kecc_aes_k_axi_top #(
	parameter int unsigned AXI_ADDR_WIDTH = 64,
	parameter int unsigned AXI_DATA_WIDTH = 64,
	parameter int unsigned AXI_ID_WIDTH,
	parameter int unsigned AXI_USER_WIDTH,
	parameter type axi_req_t = logic,
	parameter type axi_rsp_t = logic,
	// Only meaningful for v4/v5 (see the `ifdef KECC_AES_K_LOOSE_* below) -- ignored
	// for v2/v3, which don't declare these parameters on keccak_aes_k_top at all.
	parameter int unsigned SBOX_IMPL = 0,          // v4/v5: AES_SBOX_IMPL_SERIAL_ROM
	parameter int unsigned PARALLEL_SLICES = 4     // v5 only
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

	kecc_aes_k_axi_reg_pkg::kecc_aes_k_axi_reg2hw_t reg_file_to_ip;
	kecc_aes_k_axi_reg_pkg::kecc_aes_k_axi_hw2reg_t ip_to_reg_file;
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

	kecc_aes_k_axi_reg_top # (
		.reg_req_t(reg_req_t),
		.reg_rsp_t(reg_rsp_t)
	) kecc_aes_k_axi_reg_top_i (
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.reg_req_i(reg_req_i),
		.reg_rsp_o(reg_rsp_o),
		.reg2hw(reg_file_to_ip),
		.hw2reg(ip_to_reg_file),
		.devmode_i(1'b1)
	);

	// keccak_aes_k_top's init/next are single-cycle-pulse inputs, but
	// CTRL.INIT/CTRL.NEXT are software-owned, level-held bits (software
	// sets them, polls STATUS, then clears them again -- same contract as
	// the sibling keccak-only IP's CTRL.START). Edge-detect the 0->1
	// transition here to produce the pulse the core's FSM expects,
	// regardless of how long software leaves the bit asserted while
	// polling.
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

	// STATUS.READY/RESULT_VALID are level signals on the core (they stay
	// asserted from completion until the next operation starts), so they
	// are plain continuous hardware mirrors -- no latching required.
	assign ip_to_reg_file.status.ready.d          = core_ready;
	assign ip_to_reg_file.status.ready.de         = 1'b1;
	assign ip_to_reg_file.status.result_valid.d   = core_result_valid;
	assign ip_to_reg_file.status.result_valid.de  = 1'b1;

	// keccak_done is a genuine one-cycle registered pulse on the core (see
	// keccak_aes_k_top.sv), so STATUS.KECCAK_DONE latches it (hwaccess:
	// hrw, de tied to the pulse) -- software clears it by writing 0 before
	// the next Keccak op, mirroring the sibling IP's CTRL.DONE idiom.
	assign ip_to_reg_file.status.keccak_done.d  = 1'b1;
	assign ip_to_reg_file.status.keccak_done.de = core_keccak_done;

	// AES key/block: software-owned staging registers, read directly by
	// the core every cycle -- no separate copy anywhere.
	logic [255:0] core_key;
	logic [127:0] core_block;
	logic [127:0] core_result;

	genvar gk, gb, gr;
	generate
		for (gk = 0; gk < 4; gk++) begin : g_key_word
			assign core_key[64*gk +: 64] = reg_file_to_ip.key[gk].q;
		end
		for (gb = 0; gb < 2; gb++) begin : g_block_word
			assign core_block[64*gb +: 64] = reg_file_to_ip.block[gb].q;
		end
		// RESULT mirrors the core's `result` output for as long as
		// result_valid is asserted (the core holds both stable across the
		// whole idle period after a block completes) -- no edge-detect
		// needed, a continuous write gated by the level signal is enough.
		for (gr = 0; gr < 2; gr++) begin : g_result_word
			assign ip_to_reg_file.result[gr].d  = core_result[64*gr +: 64];
			assign ip_to_reg_file.result[gr].de = core_result_valid;
		end
	endgenerate

	// Pack/unpack between the register file's 25 independent KECCAK_DATA[i]
	// words and the core's flat keccak_din/keccak_dout buses: word i =
	// bits [64*i +: 64], matching keccak_aes_k_top.sv's own w=5*y+x lane
	// packing convention.
	logic [1599:0] core_keccak_din, core_keccak_dout;

	genvar gw;
	generate
		for (gw = 0; gw < 25; gw++) begin : g_keccak_word
			assign core_keccak_din[64*gw +: 64]     = reg_file_to_ip.keccak_data[gw].q;
			assign ip_to_reg_file.keccak_data[gw].d  = core_keccak_dout[64*gw +: 64];
			assign ip_to_reg_file.keccak_data[gw].de = core_keccak_done;
		end
	endgenerate

	// result_valid is level-held on the core (stays asserted from
	// completion until the next AES op starts), so it is edge-detected
	// here too, purely for the interrupt line -- otherwise the interrupt
	// would stay asserted for the whole idle period. STATUS.RESULT_VALID
	// itself (above) intentionally stays a plain level mirror; software
	// polls it directly and does not need this edge.
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

	// keccak_aes_k_top's parameter list differs by version -- v2/v3 take none, v4
	// adds SBOX_IMPL, v5 adds SBOX_IMPL + PARALLEL_SLICES (see core/Flist.cva6's
	// +define+KECC_AES_K_LOOSE_${AES_LOOSE_VERSION}, set to match whichever
	// version's -F'd flist was actually compiled in). Port list itself is
	// identical across all four versions.
`ifdef KECC_AES_K_LOOSE_v4
	keccak_aes_k_top #(
		.SBOX_IMPL (SBOX_IMPL)
	) i_keccak_aes_k_top (
`elsif KECC_AES_K_LOOSE_v5
	keccak_aes_k_top #(
		.SBOX_IMPL       (SBOX_IMPL),
		.PARALLEL_SLICES (PARALLEL_SLICES)
	) i_keccak_aes_k_top (
`else
	keccak_aes_k_top i_keccak_aes_k_top (
`endif
		.clk          (clk_i),
		.reset_n      (rst_ni),
		.zeroize      (reg_file_to_ip.ctrl.zeroize.q),

		.sel          (reg_file_to_ip.ctrl.sel.q),
		.encdec       (reg_file_to_ip.ctrl.encdec.q),
		.keylen       (reg_file_to_ip.ctrl.keylen.q),

		.init         (core_init),
		.next         (core_next),
		.ready        (core_ready),

		.key          (core_key),
		.block        (core_block),
		.result       (core_result),
		.result_valid (core_result_valid),

		.keccak_din   (core_keccak_din),
		.keccak_dout  (core_keccak_dout),
		.keccak_done  (core_keccak_done)
	);

endmodule
