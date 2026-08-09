//
// rej_sampler: hardware offload of a squeeze/mask/reject/reduce sampling
// loop, shared by two callers with different candidate conventions:
//
//   Falcon's Zf(hash_to_point_vartime)() (common.c): squeeze a 16-bit
//   BIG-endian word, reject if w >= 5*q, else reduce mod q via up to 4
//   conditional subtractions, output uint16_t samples.
//
//   ML-DSA's rej_uniform() (poly.c): squeeze a 24-bit LITTLE-endian word,
//   mask to the low 23 bits, reject if t >= q (thresh == q here -- the
//   masked candidate is already < 2^23, and the reference has no separate
//   reduction step at all), output int32_t samples.
//
// REJ_CTRL.CAND3 selects which candidate convention is in effect (0 =
// Falcon's 2-byte/big-endian/unmasked, 1 = ML-DSA's 3-byte/little-endian/
// masked-to-23-bits); REJ_CTRL.RATE168 selects the SHAKE rate this job
// squeezes from (0 = 136B/SHAKE256, 1 = 168B/SHAKE128); REJ_CTRL.OUTWIDE
// selects the output sample element width (0 = 2 bytes, 1 = 4 bytes). None
// of this needs the accept/reduce math itself to change: the reduction is
// still "up to 4 conditional subtractions", which is a correct no-op
// whenever the (masked) candidate is already below q -- true for both
// callers, since ML-DSA's thresh == q by construction (software sets
// REJ_PARAMS.THRESH = REJ_PARAMS.Q for its own calls) and Falcon's own
// thresh = 5*q keeps the same "at most 4 subtractions" bound it always had.
//
// This module implements ONLY the inner per-word loop:
//
//   while (n > 0) {
//       shake_extract(sc, buf, cand_bytes);        // <-- this module
//       w = assemble(buf, cand_bytes, endian);      // <-- this module
//       w = cand3 ? (w & 0x7FFFFF) : w;             // <-- this module
//       if (w < thresh) {                           // <-- this module
//           while (w >= q) w -= q;                  // <-- this module
//           *x++ = w; n--;                           // <-- this module
//       }
//   }
//
// The outer per-context setup (shake_init/inject, shake_flip) is left to
// software, unchanged: this job assumes the accelerator's DATA[] state is
// already hardware-resident for the caller's context, with SHAKE's
// pad10*1 bits already XORed in by shake_flip() but NOT yet permuted
// (dptr == rate) -- same precondition as every other resident-squeeze
// call site in shake.c/sha3.c.
//
// Squeeze bytes are served one at a time from the resident DATA[] word/
// lane addressed by blk_off_q (same word_rd_data bus keccak_dma_ctrl
// reads), chaining a fresh permutation whenever a draw would cross the
// selected rate boundary -- a byte-serve pattern mirroring
// keccak_dma_ctrl's own byte-at-a-time absorb engine, just with a small
// (2 or 3 byte) assembly buffer instead of arbitrary-length absorb.
//
// Accepted samples are written one element (2 or 4 bytes, per OUTWIDE) at
// a time to job_x_addr_i + elem_bytes*n_done, over the same simple
// single-outstanding req/gnt/valid memory port keccak_dma_ctrl and
// ntt_engine use (never active at the same time, so all three are muxed
// onto one external port in vrf_axi_top). job_x_addr_i is always
// caller-aligned to at least elem_bytes (see the non-cacheable
// scratch-window convention in VRF_REJ_HW_SCRATCH_ADDR, common.c; ML-DSA's
// int32_t a[] arrays are naturally 4-byte aligned), so a write never
// crosses an 8-byte word boundary.
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
    input  logic [23:0]                 job_q_i,
    input  logic [23:0]                 job_thresh_i,
    input  logic [15:0]                 job_n_i,
    input  logic                        job_cand3_i,
    input  logic                        job_rate168_i,
    input  logic                        job_outwide_i,

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
    input  logic [AXI_DATA_WIDTH-1:0]   mem_rdata_i,  // job never reads memory; port kept for bus uniformity with ntt_engine in vrf_axi_top's shared mux
    /* verilator lint_on UNUSEDSIGNAL */

    // 1 whenever a job is in progress (for external mem-port arbitration)
    output logic                        busy_o
);

  // SHAKE rate, selected per job (136 = SHAKE256/Falcon, 168 = SHAKE128/ML-DSA).
  localparam logic [7:0] RateBytes136 = 8'd136;
  localparam logic [7:0] RateBytes168 = 8'd168;

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
  logic [23:0]               q_q, q_d;
  logic [23:0]               thresh_q, thresh_d;
  logic [15:0]               n_q, n_d;
  logic [15:0]               n_done_q, n_done_d;
  logic                      cand3_q, cand3_d;
  logic                      rate168_q, rate168_d;
  logic                      outwide_q, outwide_d;

  logic [7:0]                blk_off_q, blk_off_d;   // position within the current rate block
  logic [7:0]                blk_off_next;           // blk_off_q+1, precomputed for BYTE_SERVE
  logic [7:0]                rate_bytes_l;            // selected rate boundary (136 or 168)
  logic [1:0]                cand_bytes;              // selected candidate width (2 or 3)
  // Next byte-serve slot; equals cand_bytes once the draw's last byte has
  // been served (sentinel value, one past the last valid index) -- needed
  // so PERM_WAIT can tell "wrapped mid-draw, more bytes still needed" apart
  // from "wrapped right after the draw's last byte, decision already ready".
  logic [1:0]                byte_idx_q, byte_idx_d;
  logic                      perm_initial_q, perm_initial_d;
  logic [23:0]                buf3_q, buf3_d;          // assembled candidate (2 or 3 bytes, endian per cand3_q)
  logic [23:0]                reduced_q, reduced_d;     // latched reduced value, valid while in XREQ/XWAIT

  logic job_go_rise;
  assign job_go_rise = job_go_i & ~job_go_old_q;

  assign busy_o = (state_q != IDLE) && (state_q != DONE_HOLD);

  assign rate_bytes_l = rate168_q ? RateBytes168 : RateBytes136;
  assign cand_bytes    = cand3_q ? 2'd3 : 2'd2;

  // current squeeze byte, read from the resident DATA[] word/lane addressed
  // by blk_off_q (same word_rd_data bus the absorb engine reads).
  logic [4:0] cur_word_idx;
  logic [2:0] cur_byte_lane;
  assign cur_word_idx  = blk_off_q[7:3];
  assign cur_byte_lane = blk_off_q[2:0];
  logic [7:0] cur_squeeze_byte;
  assign cur_squeeze_byte = word_rd_data_i[cur_word_idx][cur_byte_lane*8 +: 8];

  assign blk_off_next = blk_off_q + 8'd1;

  // Mask to the low 23 bits for ML-DSA's 3-byte candidate (a no-op for
  // Falcon's 2-byte candidate, which is already <= 16 bits).
  logic [23:0] cand_masked;
  assign cand_masked = cand3_q ? (buf3_q & 24'h7FFFFF) : buf3_q;

  // w < thresh reject test, and the fixed 4-stage conditional-subtract
  // reduction mod q -- mirrors Zf(hash_to_point_vartime)()'s
  // "while (w >= q) w -= q" (Falcon) / is a correct no-op for ML-DSA's
  // rej_uniform (which needs no reduction: thresh == q, so an accepted
  // candidate is already < q and 0 subtractions trigger). Bounded to 4
  // iterations because thresh <= 5*q for every caller (see module header).
  function automatic logic [23:0] rej_reduce4(
      input logic [23:0] w,
      input logic [23:0] q
  );
    logic [23:0] t;
    t = w;
    if (t >= q) t = t - q;
    if (t >= q) t = t - q;
    if (t >= q) t = t - q;
    if (t >= q) t = t - q;
    return t;
  endfunction

  logic        accept;
  logic [23:0] reduced;
  assign accept  = cand_masked < thresh_q;
  assign reduced = rej_reduce4(cand_masked, q_q);

  localparam int unsigned StrbWidth = AXI_DATA_WIDTH / 8;

  logic [AXI_ADDR_WIDTH-1:0] x_word_addr;
  logic [2:0]                x_byte_lane;
  assign x_word_addr = x_addr_q + (outwide_q ? (AXI_ADDR_WIDTH'(n_done_q) << 2)
                                              : (AXI_ADDR_WIDTH'(n_done_q) << 1));
  assign x_byte_lane = x_word_addr[2:0];

  always_comb begin
    state_d        = state_q;
    x_addr_d       = x_addr_q;
    q_d            = q_q;
    thresh_d       = thresh_q;
    n_d            = n_q;
    n_done_d       = n_done_q;
    cand3_d        = cand3_q;
    rate168_d      = rate168_q;
    outwide_d      = outwide_q;
    blk_off_d      = blk_off_q;
    byte_idx_d     = byte_idx_q;
    perm_initial_d = perm_initial_q;
    buf3_d         = buf3_q;
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
          n_done_d       = 16'd0;
          cand3_d        = job_cand3_i;
          rate168_d      = job_rate168_i;
          outwide_d      = job_outwide_i;
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
          end else if (byte_idx_q == cand_bytes) begin
            // the block wrap coincided exactly with the draw's last byte --
            // it's already assembled, so go straight to the accept/reject
            // decision instead of serving a (nonexistent) further byte.
            state_d = DECIDE;
          end else begin
            state_d = BYTE_SERVE;
          end
        end
      end

      BYTE_SERVE: begin
        // Byte assembly order: Falcon (cand3_q=0) is big-endian, 2 bytes
        // (byte 0 -> bits[15:8]); ML-DSA (cand3_q=1) is little-endian, 3
        // bytes (byte 0 -> bits[7:0]).
        if (cand3_q) begin
          buf3_d[8*byte_idx_q +: 8] = cur_squeeze_byte;
        end else begin
          if (byte_idx_q == 2'd0) begin
            buf3_d[15:8] = cur_squeeze_byte;
          end else begin
            buf3_d[7:0] = cur_squeeze_byte;
          end
        end
        byte_idx_d = byte_idx_q + 2'd1;
        if (blk_off_next == rate_bytes_l) begin
          blk_off_d      = 8'd0;
          perm_initial_d = 1'b0;
          state_d        = PERM_START;
        end else begin
          blk_off_d = blk_off_next;
          state_d   = (byte_idx_q + 2'd1 == cand_bytes) ? DECIDE : BYTE_SERVE;
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
        if (outwide_q) begin
          mem_wdata_o = {2{8'h00, reduced_q}};
          mem_be_o    = StrbWidth'(4'hF) << x_byte_lane;
        end else begin
          mem_wdata_o = {4{reduced_q[15:0]}};
          mem_be_o    = StrbWidth'(4'h3) << x_byte_lane;
        end
        if (mem_gnt_i) begin
          state_d = XWAIT;
        end
      end

      XWAIT: begin
        if (mem_valid_i) begin
          if (n_done_q + 16'd1 == n_q) begin
            state_d = DONE_HOLD;
          end else begin
            n_done_d = n_done_q + 16'd1;
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
      cand3_q        <= 1'b0;
      rate168_q      <= 1'b0;
      outwide_q      <= 1'b0;
      blk_off_q      <= '0;
      byte_idx_q     <= 2'd0;
      perm_initial_q <= 1'b0;
      buf3_q         <= '0;
      reduced_q      <= '0;
    end else begin
      state_q        <= state_d;
      job_go_old_q   <= job_go_i;
      x_addr_q       <= x_addr_d;
      q_q            <= q_d;
      thresh_q       <= thresh_d;
      n_q            <= n_d;
      n_done_q       <= n_done_d;
      cand3_q        <= cand3_d;
      rate168_q      <= rate168_d;
      outwide_q      <= outwide_d;
      blk_off_q      <= blk_off_d;
      byte_idx_q     <= byte_idx_d;
      perm_initial_q <= perm_initial_d;
      buf3_q         <= buf3_d;
      reduced_q      <= reduced_d;
    end
  end

endmodule : rej_sampler
