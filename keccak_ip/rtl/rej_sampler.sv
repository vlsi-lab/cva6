//
// rej_sampler: hardware offload of Falcon's Zf(hash_to_point_vartime)()
// (common.c) rejection-sampling loop -- squeeze a 16-bit big-endian word,
// reject if w >= 5*q, else reduce mod q via conditional subtraction, and
// keep going until n accepted samples have been produced. HAWK has no
// equivalent pattern anywhere in KeyGen/Sign/Verify (checked directly
// against ng_mp31.c/ng_fxp.c/hawk_sign.c/hawk_vrfy.c) so this job is
// currently exercised by Falcon Verify only; the register interface is
// generic (job_q_i/job_thresh_i are plain per-job values, not a hardwired
// q=12289) so a future HAWK use is a software integration exercise, not
// an RTL change.
//
// This module implements ONLY the inner per-word loop:
//
//   while (n > 0) {
//       shake_extract(sc, buf, 2);            // <-- this module
//       w = (buf[0] << 8) | buf[1];           // <-- this module
//       if (w < thresh) {                     // <-- this module
//           while (w >= q) w -= q;            // <-- this module
//           *x++ = w; n--;                    // <-- this module
//       }
//   }
//
// The outer per-context setup (shake_init/inject, shake_flip) is left to
// software, unchanged: this job assumes the accelerator's DATA[] state is
// already hardware-resident for the caller's context, with SHAKE's
// pad10*1 bits already XORed in by shake_flip() but NOT yet permuted
// (dptr == rate) -- identical precondition to gauss_sampler's job, and to
// every other resident-squeeze call site in shake.c/sha3.c.
//
// Squeeze bytes are served one at a time from the resident DATA[] word/
// lane addressed by blk_off_q (same word_rd_data bus keccak_dma_ctrl and
// gauss_sampler read), chaining a fresh permutation whenever a 2-byte draw
// would cross the 136-byte SHAKE256 rate boundary -- this directly mirrors
// gauss_sampler's BYTE_SERVE state, just with a 2-byte assembly buffer
// instead of a 40-byte one.
//
// Accepted samples are written one 16-bit halfword at a time to
// job_x_addr_i + 2*n_done, over the same simple single-outstanding
// req/gnt/valid memory port keccak_dma_ctrl/gauss_sampler use (never
// active at the same time, so all three are muxed onto one external port
// in keccak_axi_top). job_x_addr_i is always caller-aligned to an even
// byte (see the non-cacheable scratch-window convention in
// FALCON_REJ_HW_SCRATCH_ADDR, common.c), so a 2-byte write never crosses
// an 8-byte word boundary.
//
// The rejection bound (w < thresh, thresh = 5*q for Falcon) is a job
// parameter, not hardcoded, so a modulus other than q=12289 works without
// RTL changes as long as thresh/q keep the "at most 4 conditional
// subtractions reduce it" property (true whenever thresh <= 5*q, which is
// what makes the reference software's own `while (w >= q) w -= q` loop
// bounded in the first place).
//
module rej_sampler #(
    parameter int unsigned AXI_ADDR_WIDTH = 64,
    parameter int unsigned AXI_DATA_WIDTH = 64
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,

    // job descriptor, read from the register file
    input  logic                        job_go_i,
    input  logic [AXI_ADDR_WIDTH-1:0]   job_x_addr_i,
    input  logic [15:0]                 job_q_i,
    input  logic [15:0]                 job_thresh_i,
    input  logic [31:0]                 job_n_i,

    // job status, latched until software clears REJ_CTRL.GO
    output logic                        job_done_o,

    // current DATA[] contents (same word_rd_data bus keccak_dma_ctrl reads)
    input  logic [24:0][AXI_DATA_WIDTH-1:0] word_rd_data_i,

    // permutation control: pulse to trigger, level while it is running
    output logic                        perm_start_o,
    input  logic                        perm_done_i,

    // simple single-outstanding memory-like master port
    output logic                        mem_req_o,
    output logic [AXI_ADDR_WIDTH-1:0]   mem_addr_o,
    output logic                        mem_we_o,
    output logic [AXI_DATA_WIDTH-1:0]   mem_wdata_o,
    output logic [AXI_DATA_WIDTH/8-1:0] mem_be_o,
    input  logic                        mem_gnt_i,
    input  logic                        mem_valid_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [AXI_DATA_WIDTH-1:0]   mem_rdata_i,  // job never reads memory; port kept for bus uniformity with ntt_engine/gauss_sampler in keccak_axi_top's shared mux
    /* verilator lint_on UNUSEDSIGNAL */

    // 1 whenever a job is in progress (for external mem-port arbitration)
    output logic                        busy_o
);

  // SHAKE256 rate, same as keccak_dma_ctrl/gauss_sampler.
  localparam int unsigned RateBytes  = 136;
  localparam logic [7:0]  RateBytesL = 8'(RateBytes);

  typedef enum logic [3:0] {
    IDLE,
    PERM_START,
    PERM_WAIT,
    BYTE_SERVE,
    DECIDE,
    XREQ,
    XWAIT,
    DONE_HOLD
  } state_e;

  state_e state_q, state_d;

  logic                      job_go_old_q;
  logic [AXI_ADDR_WIDTH-1:0] x_addr_q, x_addr_d;
  logic [15:0]               q_q, q_d;
  logic [15:0]               thresh_q, thresh_d;
  logic [31:0]               n_q, n_d;
  logic [31:0]               n_done_q, n_done_d;

  logic [7:0]                blk_off_q, blk_off_d;   // position within the current rate block
  logic [7:0]                blk_off_next;           // blk_off_q+1, precomputed for BYTE_SERVE
  // 0/1 = next slot to write (hi/lo); 2 = both slots written (sentinel,
  // unreachable as a "next slot" value -- needed, exactly as in
  // gauss_sampler's wider byte_idx_q, so PERM_WAIT can tell "wrapped after
  // the hi byte, lo byte still needed" (byte_idx_q==1) apart from
  // "wrapped right after the lo byte, draw already complete"
  // (byte_idx_q==2) instead of both aliasing to the same 1-bit value.
  logic [1:0]                byte_idx_q, byte_idx_d;
  logic                      perm_initial_q, perm_initial_d;
  logic [15:0]                buf2_q, buf2_d;         // assembled 2-byte squeeze word (buf[0]<<8|buf[1])
  logic [15:0]                reduced_q, reduced_d;    // latched reduced value, valid while in XREQ/XWAIT

  logic job_go_rise;
  assign job_go_rise = job_go_i & ~job_go_old_q;

  assign busy_o = (state_q != IDLE) && (state_q != DONE_HOLD);

  // current squeeze byte, read from the resident DATA[] word/lane addressed
  // by blk_off_q (same word_rd_data bus the absorb engine reads).
  logic [4:0] cur_word_idx;
  logic [2:0] cur_byte_lane;
  assign cur_word_idx  = blk_off_q[7:3];
  assign cur_byte_lane = blk_off_q[2:0];
  logic [7:0] cur_squeeze_byte;
  assign cur_squeeze_byte = word_rd_data_i[cur_word_idx][cur_byte_lane*8 +: 8];

  assign blk_off_next = blk_off_q + 8'd1;

  // w < thresh reject test, and the fixed 4-stage conditional-subtract
  // reduction mod q -- mirrors Zf(hash_to_point_vartime)()'s
  // "while (w >= q) w -= q" exactly; bounded to 4 iterations because
  // thresh <= 5*q for every caller (see module header).
  function automatic logic [15:0] rej_reduce4(
      input logic [15:0] w,
      input logic [15:0] q
  );
    logic [15:0] t;
    t = w;
    if (t >= q) t = t - q;
    if (t >= q) t = t - q;
    if (t >= q) t = t - q;
    if (t >= q) t = t - q;
    return t;
  endfunction

  logic        accept;
  logic [15:0] reduced;
  assign accept  = buf2_q < thresh_q;
  assign reduced = rej_reduce4(buf2_q, q_q);

  localparam int unsigned StrbWidth = AXI_DATA_WIDTH / 8;

  logic [AXI_ADDR_WIDTH-1:0] x_word_addr;
  logic [2:0]                x_byte_lane;
  assign x_word_addr = x_addr_q + (AXI_ADDR_WIDTH'(n_done_q) << 1);
  assign x_byte_lane = x_word_addr[2:0];

  always_comb begin
    state_d        = state_q;
    x_addr_d       = x_addr_q;
    q_d            = q_q;
    thresh_d       = thresh_q;
    n_d            = n_q;
    n_done_d       = n_done_q;
    blk_off_d      = blk_off_q;
    byte_idx_d     = byte_idx_q;
    perm_initial_d = perm_initial_q;
    buf2_d         = buf2_q;
    reduced_d      = reduced_q;

    perm_start_o = 1'b0;
    job_done_o   = 1'b0;

    mem_req_o   = 1'b0;
    mem_addr_o  = x_word_addr;
    mem_we_o    = 1'b0;
    mem_wdata_o = '0;
    mem_be_o    = '0;

    unique case (state_q)
      IDLE: begin
        if (job_go_rise) begin
          x_addr_d       = job_x_addr_i;
          q_d            = job_q_i;
          thresh_d       = job_thresh_i;
          n_d            = job_n_i;
          n_done_d       = 32'd0;
          perm_initial_d = 1'b1;
          state_d        = PERM_START;
        end
      end

      PERM_START: begin
        perm_start_o = 1'b1;
        state_d      = PERM_WAIT;
      end

      PERM_WAIT: begin
        if (perm_done_i) begin
          blk_off_d = 8'd0;
          if (perm_initial_q) begin
            byte_idx_d     = 2'd0;
            perm_initial_d = 1'b0;
            state_d        = BYTE_SERVE;
          end else if (byte_idx_q == 2'd2) begin
            // the block wrap coincided exactly with the 2nd (last) byte
            // this draw needed -- both bytes are already assembled, so go
            // straight to the accept/reject decision instead of serving a
            // (nonexistent) further byte.
            state_d = DECIDE;
          end else begin
            state_d = BYTE_SERVE;
          end
        end
      end

      BYTE_SERVE: begin
        if (byte_idx_q == 2'd0) begin
          buf2_d[15:8] = cur_squeeze_byte;
        end else begin
          buf2_d[7:0] = cur_squeeze_byte;
        end
        byte_idx_d = byte_idx_q + 2'd1;
        if (blk_off_next == RateBytesL) begin
          blk_off_d      = 8'd0;
          perm_initial_d = 1'b0;
          state_d        = PERM_START;
        end else begin
          blk_off_d = blk_off_next;
          state_d   = (byte_idx_q == 2'd1) ? DECIDE : BYTE_SERVE;
        end
      end

      DECIDE: begin
        byte_idx_d = 2'd0;
        if (accept) begin
          reduced_d = reduced;
          state_d   = XREQ;
        end else begin
          state_d = BYTE_SERVE;
        end
      end

      XREQ: begin
        mem_req_o   = 1'b1;
        mem_addr_o  = x_word_addr;
        mem_we_o    = 1'b1;
        mem_wdata_o = {4{reduced_q}};
        mem_be_o    = StrbWidth'(3) << x_byte_lane;
        if (mem_gnt_i) begin
          state_d = XWAIT;
        end
      end

      XWAIT: begin
        if (mem_valid_i) begin
          if (n_done_q + 32'd1 == n_q) begin
            state_d = DONE_HOLD;
          end else begin
            n_done_d = n_done_q + 32'd1;
            state_d  = BYTE_SERVE;
          end
        end
      end

      DONE_HOLD: begin
        job_done_o = 1'b1;
        if (!job_go_i) begin
          state_d = IDLE;
        end
      end

      default: state_d = IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= IDLE;
      job_go_old_q   <= 1'b0;
      x_addr_q       <= '0;
      q_q            <= '0;
      thresh_q       <= '0;
      n_q            <= '0;
      n_done_q       <= '0;
      blk_off_q      <= '0;
      byte_idx_q     <= 2'd0;
      perm_initial_q <= 1'b0;
      buf2_q         <= '0;
      reduced_q      <= '0;
    end else begin
      state_q        <= state_d;
      job_go_old_q   <= job_go_i;
      x_addr_q       <= x_addr_d;
      q_q            <= q_d;
      thresh_q       <= thresh_d;
      n_q            <= n_d;
      n_done_q       <= n_done_d;
      blk_off_q      <= blk_off_d;
      byte_idx_q     <= byte_idx_d;
      perm_initial_q <= perm_initial_d;
      buf2_q         <= buf2_d;
      reduced_q      <= reduced_d;
    end
  end

endmodule : rej_sampler
