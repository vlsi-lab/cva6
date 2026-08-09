// VRF Accelerator IP - Loosely
// Top module description for the AXI accellerator. Shared verify-only
// accelerator: one keccak_f permutation core serves four job front-ends
// (DMA-absorb/CSREG raw-permute, NTT/iNTT, rejection sampler, and the
// SPHINCS+ hash-chain job via chain_job_ctrl).
// Author: Federico Runco

`ifdef SYNTHESIS
	`include "./register_interface/typedef.svh"
	`include "./register_interface/assign.svh"
`else
	`include "/register_interface/typedef.svh"
	`include "/register_interface/assign.svh"
`endif

module vrf_axi_top
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

	output 	logic 		vrf_intr_o,

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

	vrf_reg_pkg::vrf_reg2hw_t reg_file_to_ip;
	vrf_reg_pkg::vrf_hw2reg_t ip_to_reg_file;
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

	vrf_reg_top # (
		.reg_req_t(reg_req_t),
		.reg_rsp_t(reg_rsp_t)
	) vrf_reg_top_i (
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
	logic rej_perm_start;
	logic chain_perm_start;
	logic chain_active;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			csreg_start_old <= 1'b0;
		end else begin
			csreg_start_old <= reg_file_to_ip.csreg.start.q;
		end
	end
	logic csreg_start_rise;
	assign csreg_start_rise = reg_file_to_ip.csreg.start.q & ~csreg_start_old;

	// four independent triggers share the permutation core: software polling
	// CSREG directly (legacy raw-permute path), the DMA job engine chaining
	// permutations autonomously as it fills rate blocks, the rejection
	// sampler job doing the same for its own squeeze loop, and the SPHINCS+
	// hash-chain job (chain_job_ctrl) doing the same for THASH1/THASH2/
	// PRF_ADDR. Software drives at most one job at a time, so no priority
	// scheme beyond a plain OR is needed.
	assign keccak_start = csreg_start_rise | dma_perm_start | rej_perm_start | chain_perm_start;

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
		.keccak_intr(vrf_intr_o)
	);

	// While a chain job is active, the shared core's input comes from
	// chain_job_ctrl's own SHAKE-chain absorption state, not the resident
	// DATA[] bank (the chain job is a self-contained per-call computation,
	// unlike DMA absorb which genuinely operates on persistent DATA[] state).
	logic [1599:0] chain_din;
	assign keccak_din = chain_active ? chain_din : reg_file_to_ip.data;

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
	// the DMA absorb engine and the other accelerator jobs never run at the
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
		.job_rate168_i  (reg_file_to_ip.jobctrl.rate168.q),
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

	// mp_NTT()/mp_iNTT() hardware accelerator (see ntt_engine.sv header for
	// scope/assumptions). It never runs at the same time as the DMA absorb
	// engine (software drives one job at a time), so it is muxed onto the
	// same single mem master port. It no longer touches the shared DATA[]
	// array at all: batch staging is dedicated registers inside
	// ntt_engine.sv itself.
	logic                        ntt_done, ntt_busy;
	logic                        ntt_mem_req, ntt_mem_we;
	logic [AXI_ADDR_WIDTH-1:0]   ntt_mem_addr;
	logic [AXI_DATA_WIDTH-1:0]   ntt_mem_wdata;
	logic [AXI_DATA_WIDTH/8-1:0] ntt_mem_be;

	ntt_engine #(
		.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
		.AXI_DATA_WIDTH(AXI_DATA_WIDTH)
	) i_ntt_engine (
		.clk_i           (clk_i),
		.rst_ni          (rst_ni),
		.job_go_i        (reg_file_to_ip.ntt_ctrl.go.q),
		.job_a_addr_i    (reg_file_to_ip.ntt_a_addr.q),
		.job_gm_addr_i   (reg_file_to_ip.ntt_gm_addr.q),
		.job_logn_i      (reg_file_to_ip.ntt_logn.q),
		.job_p_val_i     (reg_file_to_ip.ntt_p_val.q),
		.job_p0i_val_i   (reg_file_to_ip.ntt_p0i_val.q),
		.job_mode_i      (reg_file_to_ip.ntt_ctrl.mode.q),
		.job_noscale_i   (reg_file_to_ip.ntt_ctrl.noscale.q),
		.job_done_o      (ntt_done),
		.mem_req_o       (ntt_mem_req),
		.mem_addr_o      (ntt_mem_addr),
		.mem_we_o        (ntt_mem_we),
		.mem_wdata_o     (ntt_mem_wdata),
		.mem_be_o        (ntt_mem_be),
		.mem_gnt_i       (dma_gnt_i),
		.mem_valid_i     (dma_valid_i),
		.mem_rdata_i     (dma_rdata_i),
		.busy_o          (ntt_busy)
	);

	assign ip_to_reg_file.ntt_ctrl.done.d  = ntt_done;
	assign ip_to_reg_file.ntt_ctrl.done.de = ntt_done;

	// Falcon Zf(hash_to_point_vartime)() rejection-sampler job (see
	// rej_sampler.sv header for scope/assumptions). Like the NTT engine,
	// it never runs at the same time as the other jobs (software drives
	// one job at a time), so it shares the same single mem master port
	// and permutation trigger.
	logic                        rej_done, rej_busy;
	logic                        rej_mem_req, rej_mem_we;
	logic [AXI_ADDR_WIDTH-1:0]   rej_mem_addr;
	logic [AXI_DATA_WIDTH-1:0]   rej_mem_wdata;
	logic [AXI_DATA_WIDTH/8-1:0] rej_mem_be;

	rej_sampler #(
		.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
		.AXI_DATA_WIDTH(AXI_DATA_WIDTH)
	) i_rej_sampler (
		.clk_i          (clk_i),
		.rst_ni         (rst_ni),
		.job_go_i       (reg_file_to_ip.rej_ctrl.go.q),
		.job_x_addr_i   (reg_file_to_ip.rej_x_addr.q),
		.job_q_i        (reg_file_to_ip.rej_params.q.q),
		.job_thresh_i   (reg_file_to_ip.rej_params.thresh.q),
		.job_n_i        (reg_file_to_ip.rej_params.n.q),
		.job_cand3_i    (reg_file_to_ip.rej_ctrl.cand3.q),
		.job_rate168_i  (reg_file_to_ip.rej_ctrl.rate168.q),
		.job_outwide_i  (reg_file_to_ip.rej_ctrl.outwide.q),
		.job_done_o     (rej_done),
		.word_rd_data_i (dma_word_rd_data),
		.perm_start_o   (rej_perm_start),
		.perm_done_i    (keccak_done),
		.mem_req_o      (rej_mem_req),
		.mem_addr_o     (rej_mem_addr),
		.mem_we_o       (rej_mem_we),
		.mem_wdata_o    (rej_mem_wdata),
		.mem_be_o       (rej_mem_be),
		.mem_gnt_i      (dma_gnt_i),
		.mem_valid_i    (dma_valid_i),
		.mem_rdata_i    (dma_rdata_i),
		.busy_o         (rej_busy)
	);

	assign ip_to_reg_file.rej_ctrl.done.d  = rej_done;
	assign ip_to_reg_file.rej_ctrl.done.de = rej_done;

	assign dma_req_o   = ntt_busy ? ntt_mem_req   : (rej_busy ? rej_mem_req   : dma_mem_req);
	assign dma_addr_o  = ntt_busy ? ntt_mem_addr  : (rej_busy ? rej_mem_addr  : dma_mem_addr);
	assign dma_we_o    = ntt_busy ? ntt_mem_we    : (rej_busy ? rej_mem_we    : dma_mem_we);
	assign dma_wdata_o = ntt_busy ? ntt_mem_wdata : (rej_busy ? rej_mem_wdata : dma_mem_wdata);
	assign dma_be_o    = ntt_busy ? ntt_mem_be    : (rej_busy ? rej_mem_be    : dma_mem_be);

	genvar i;
	generate
		for (i=0; i < 25; i++) begin
			// priority: permutation output (post-round state, latched every
			// time a chained or legacy-path permutation finishes) beats the
			// DMA engine's own bulk-zero/XOR-absorb writes -- the two never
			// actually coincide in the same cycle (the DMA FSM only issues
			// a write while parked waiting on the permutation), but this
			// keeps the mux well-defined regardless. Excluded whenever a
			// chain job is active: that permutation's output belongs to
			// chain_job_ctrl's own working registers, not the resident
			// DATA[] bank (see chain_active_o's header comment in
			// chain_job_ctrl.sv).
			assign ip_to_reg_file.data[i].d =
				keccak_done  ? keccak_dout[(i+1)*64-1 -: 64] :
				dma_zero_all ? 64'd0 :
				               dma_word_data;
			assign ip_to_reg_file.data[i].de =
				(keccak_done & ~chain_active) | dma_zero_all | (dma_word_wr_en & (dma_word_idx == 5'(i)));
		end
	endgenerate

	// ── SPHINCS+/SLH-DSA hash-chain job (chain_job_ctrl.sv) ────────────────
	// Shares the same keccak_f core as the other three jobs above; never
	// runs concurrently with them (software drives one job at a time).
	// Unlike DMA/NTT/rej-sampler it has no external memory master port --
	// all its operands/results live in the CHAIN_SEED/CHAIN_ADRS/CHAIN_IN2/
	// CHAIN_IO registers.
	logic [3:0][63:0] chain_seed_rd, chain_adrs_rd, chain_in2_rd, chain_io_rd;
	genvar k;
	generate
		for (k = 0; k < 4; k++) begin : gen_chain_rd
			assign chain_seed_rd[k] = reg_file_to_ip.chain_seed[k].q;
			assign chain_adrs_rd[k] = reg_file_to_ip.chain_adrs[k].q;
			assign chain_in2_rd[k]  = reg_file_to_ip.chain_in2[k].q;
			assign chain_io_rd[k]   = reg_file_to_ip.chain_io[k].q;
		end
	endgenerate

	logic chain_done;
	logic [3:0][63:0] chain_io_wr_data;
	logic [3:0]       chain_io_wr_en;

	chain_job_ctrl i_chain_job_ctrl (
		.clk_i             (clk_i),
		.rst_ni            (rst_ni),
		.job_go_i          (reg_file_to_ip.chain_ctrl.go.q),
		.job_op_type_i     (reg_file_to_ip.chain_ctrl.op_type.q),
		.job_n_i           (reg_file_to_ip.chain_ctrl.n.q),
		.job_steps_i       (reg_file_to_ip.chain_ctrl.steps.q),
		.job_step_start_i  (reg_file_to_ip.chain_ctrl.step_start.q),
		.job_robust_i      (reg_file_to_ip.chain_ctrl.robust.q),
		.job_done_o        (chain_done),
		.seed_rd_i         (chain_seed_rd),
		.adrs_rd_i         (chain_adrs_rd),
		.chain2_rd_i       (chain_in2_rd),
		.chain_io_rd_i     (chain_io_rd),
		.chain_io_wr_data_o(chain_io_wr_data),
		.chain_io_wr_en_o  (chain_io_wr_en),
		.perm_start_o      (chain_perm_start),
		.perm_done_i       (keccak_done),
		.perm_dout_i       (keccak_dout),
		.chain_din_o       (chain_din),
		.chain_active_o    (chain_active)
	);

	assign ip_to_reg_file.chain_ctrl.done.d  = chain_done;
	assign ip_to_reg_file.chain_ctrl.done.de = chain_done;

	genvar m;
	generate
		for (m = 0; m < 4; m++) begin : gen_chain_io_wr
			assign ip_to_reg_file.chain_io[m].d  = chain_io_wr_data[m];
			assign ip_to_reg_file.chain_io[m].de = chain_io_wr_en[m];
		end
	endgenerate

endmodule