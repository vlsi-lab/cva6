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

	output 	logic 		keccak_intr_o,

	// DMA master port (simple single-outstanding req/gnt/valid interface,
	// wrapped with axi_adapter one level up to produce a real AXI4 master)
	output	logic 					dma_req_o,
	output	logic [AXI_ADDR_WIDTH-1:0] 		dma_addr_o,
	output	logic 					dma_we_o,
	output	logic [AXI_DATA_WIDTH-1:0] 		dma_wdata_o,
	output	logic [AXI_DATA_WIDTH/8-1:0] 		dma_be_o,
	input	logic 					dma_gnt_i,
	input	logic 					dma_valid_i,
	input	logic [AXI_DATA_WIDTH-1:0] 		dma_rdata_i
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
	logic dma_perm_start;
	logic samp_perm_start;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			csreg_start_old <= 1'b0;
		end else begin
			csreg_start_old <= reg_file_to_ip.csreg.start.q;
		end
	end
	logic csreg_start_rise;
	assign csreg_start_rise = reg_file_to_ip.csreg.start.q & ~csreg_start_old;

	// three independent triggers share the permutation core: software polling
	// CSREG directly (legacy raw-permute path), the DMA job engine chaining
	// permutations autonomously as it fills rate blocks, and the Gaussian
	// sampler job chaining permutations as it squeezes rate blocks
	assign keccak_start = csreg_start_rise | dma_perm_start | samp_perm_start;

	// csreg.done must only latch when THIS permutation was actually
	// triggered via CSREG.START -- keccak_done also pulses for
	// dma_perm_start-triggered (job-engine-internal, chained) permutations,
	// and since csreg.done otherwise has no way to self-clear, a DMA-chained
	// completion would leave it stale-1 until software's next explicit
	// zero-write. A software poll starting a genuine CSREG-triggered
	// permutation shortly after any multi-block DMA absorb job would then
	// see that stale bit and exit immediately, before this permutation
	// (still mid-round) actually finishes.
	logic csreg_perm_pending;
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			csreg_perm_pending <= 1'b0;
		end else if (csreg_start_rise) begin
			csreg_perm_pending <= 1'b1;
		end else if (keccak_done) begin
			csreg_perm_pending <= 1'b0;
		end
	end
	assign ip_to_reg_file.csreg.done.d  = keccak_done;
	assign ip_to_reg_file.csreg.done.de = keccak_done & csreg_perm_pending;

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

	// DMA job engine: DMA-absorbs reg_file_to_ip.job_src_len bytes from
	// reg_file_to_ip.job_src_addr straight out of CVA6 memory, XOR-absorbing
	// into the resident DATA[] state and chaining the shared permutation
	// core across rate-block boundaries, word-write-arbitrated below
	// against the permutation-output write path.
	logic        keccak_dma_done;
	logic [4:0]  dma_word_idx;
	logic [63:0] dma_word_data;
	logic        dma_word_wr_en;
	logic        dma_zero_all;
	logic [24:0][63:0] dma_word_rd_data;

	genvar j;
	generate
		for (j = 0; j < 25; j++) begin : gen_word_rd
			assign dma_word_rd_data[j] = reg_file_to_ip.data[j].q;
		end
	endgenerate

	// mem master port is a single physical AXI master (wrapped one level up);
	// the DMA absorb engine and the Gaussian sampler job never run at the
	// same time (software drives one job at a time), so they are muxed onto
	// it below rather than needing a second master port through the xbar.
	logic                        dma_mem_req, dma_mem_we;
	logic [AXI_ADDR_WIDTH-1:0]   dma_mem_addr;
	logic [AXI_DATA_WIDTH-1:0]   dma_mem_wdata;
	logic [AXI_DATA_WIDTH/8-1:0] dma_mem_be;

	keccak_dma_ctrl #(
		.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
		.AXI_DATA_WIDTH(AXI_DATA_WIDTH)
	) i_keccak_dma_ctrl (
		.clk_i          (clk_i),
		.rst_ni         (rst_ni),
		.job_go_i       (reg_file_to_ip.jobctrl.go.q),
		.job_src_addr_i (reg_file_to_ip.job_src_addr.q),
		.job_src_len_i  (reg_file_to_ip.job_src_len.q),
		.job_fresh_i    (reg_file_to_ip.jobctrl.fresh.q),
		.job_flip_i     (reg_file_to_ip.jobctrl.flip.q),
		.job_dptr_i     (reg_file_to_ip.jobctrl.dptr.q),
		.job_done_o     (keccak_dma_done),
		.word_wr_idx_o  (dma_word_idx),
		.word_wr_data_o (dma_word_data),
		.word_wr_en_o   (dma_word_wr_en),
		.zero_all_o     (dma_zero_all),
		.word_rd_data_i (dma_word_rd_data),
		.perm_start_o   (dma_perm_start),
		.perm_done_i    (keccak_done),
		.mem_req_o      (dma_mem_req),
		.mem_addr_o     (dma_mem_addr),
		.mem_we_o       (dma_mem_we),
		.mem_wdata_o    (dma_mem_wdata),
		.mem_be_o       (dma_mem_be),
		.mem_gnt_i      (dma_gnt_i),
		.mem_valid_i    (dma_valid_i),
		.mem_rdata_i    (dma_rdata_i)
	);

	assign ip_to_reg_file.jobctrl.done.d  = keccak_dma_done;
	assign ip_to_reg_file.jobctrl.done.de = keccak_dma_done;

	// HAWK sig_gauss() CDT hardware sampler job (HAWK-256 only -- see
	// gauss_sampler.sv header for scope/assumptions).
	logic                        samp_done, samp_busy;
	logic [31:0]                 samp_sn;
	logic                        samp_mem_req, samp_mem_we;
	logic [AXI_ADDR_WIDTH-1:0]   samp_mem_addr;
	logic [AXI_DATA_WIDTH-1:0]   samp_mem_wdata;
	logic [AXI_DATA_WIDTH/8-1:0] samp_mem_be;

	gauss_sampler #(
		.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
		.AXI_DATA_WIDTH(AXI_DATA_WIDTH)
	) i_gauss_sampler (
		.clk_i          (clk_i),
		.rst_ni         (rst_ni),
		.job_go_i       (reg_file_to_ip.samp_ctrl.go.q),
		.job_t_addr_i   (reg_file_to_ip.samp_t_addr.q),
		.job_x_addr_i   (reg_file_to_ip.samp_x_addr.q),
		.job_bitbase_i  (reg_file_to_ip.samp_bitbase.q),
		.job_nblocks_i  (reg_file_to_ip.samp_nblocks.q),
		.job_done_o     (samp_done),
		.job_sn_o       (samp_sn),
		.word_rd_data_i (dma_word_rd_data),
		.perm_start_o   (samp_perm_start),
		.perm_done_i    (keccak_done),
		.mem_req_o      (samp_mem_req),
		.mem_addr_o     (samp_mem_addr),
		.mem_we_o       (samp_mem_we),
		.mem_wdata_o    (samp_mem_wdata),
		.mem_be_o       (samp_mem_be),
		.mem_gnt_i      (dma_gnt_i),
		.mem_valid_i    (dma_valid_i),
		.mem_rdata_i    (dma_rdata_i),
		.busy_o         (samp_busy)
	);

	assign ip_to_reg_file.samp_ctrl.done.d  = samp_done;
	assign ip_to_reg_file.samp_ctrl.done.de = samp_done;
	assign ip_to_reg_file.samp_sn.d         = samp_sn;
	assign ip_to_reg_file.samp_sn.de        = samp_done;

	assign dma_req_o   = samp_busy ? samp_mem_req   : dma_mem_req;
	assign dma_addr_o  = samp_busy ? samp_mem_addr  : dma_mem_addr;
	assign dma_we_o    = samp_busy ? samp_mem_we    : dma_mem_we;
	assign dma_wdata_o = samp_busy ? samp_mem_wdata : dma_mem_wdata;
	assign dma_be_o    = samp_busy ? samp_mem_be    : dma_mem_be;

	genvar i;
	generate
		for (i=0; i < 25; i++) begin
			// priority: permutation output (post-round state, latched every
			// time a chained or legacy-path permutation finishes) beats the
			// DMA engine's own bulk-zero/XOR-absorb writes -- the two never
			// actually coincide in the same cycle (the DMA FSM only issues
			// a write while parked waiting on the permutation), but this
			// keeps the mux well-defined regardless.
			assign ip_to_reg_file.data[i].d =
				keccak_done  ? keccak_dout[(i+1)*64-1 -: 64] :
				dma_zero_all ? 64'd0 :
				               dma_word_data;
			assign ip_to_reg_file.data[i].de =
				keccak_done | dma_zero_all | (dma_word_wr_en & (dma_word_idx == 5'(i)));
		end
	endgenerate

endmodule