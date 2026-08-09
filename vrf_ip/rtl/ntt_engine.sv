//
// ntt_engine: hardware offload of mp_NTT()/mp_iNTT() (ng_mp31.c, non-AVX2
// path -- the one CVA6 actually compiles), the shared primitive kernel
// used by Falcon's Verify path (mq_NTT_hw()/mq_iNTT_hw(), see
// tests/falcon512-opt/vrfy.c and tests/falcon1024-opt/vrfy.c) via the
// generic 32-bit-domain Montgomery NTT/iNTT engine below.
//
// Algorithm (verified against ng_mp31.c/ng_inner.h, not re-derived from
// memory -- mp_NTT and mp_iNTT are NOT mirror images of each other in the
// way a naive reading of "inverse NTT" might suggest):
//
//   mp_NTT (Cooley-Tukey, decimation-in-time): for each of logn stages,
//     t halves (starts at n), m=1<<lm doubles (starts at 1). Per butterfly:
//       x2' = montymul(a[k2], s);  a[k1] = add(x1,x2');  a[k2] = sub(x1,x2');
//
//   mp_iNTT (Gentleman-Sande, decimation-in-frequency): for each of logn
//     stages, t doubles (starts at 1), hm=1<<(logn-1-lm) halves (starts at
//     n/2). Per butterfly:
//       a[k1] = half(add(x1,x2));  a[k2] = montymul(sub(x1,x2), s);
//     Critically, mp_iNTT's non-AVX2 path has NO separate final n^-1
//     scaling pass -- the n^-1 factor is distributed across all logn
//     stages via mp_half() on the sum side of every single butterfly.
//     This is job_noscale_i=0 (the default, Falcon's own convention).
//
//   NTT_CTRL.NOSCALE (job_noscale_i, inverse mode only): ML-DSA's reference
//     invntt_tomont() uses a DIFFERENT convention for the same
//     Cooley-Tukey/Gentleman-Sande butterfly shape -- no per-stage scaling
//     at all (a plain sum on the k1 side, matching mp_NTT/mp_iNTT's
//     structural shape but not the Falcon-specific half()), with a single
//     combined n^-1/Montgomery-domain correction multiply left entirely to
//     software after the transform. job_noscale_i=1 selects this behavior
//     (skips mp_half_f on the k1 side); it is ignored in forward mode,
//     which never scales either way.
//
// Both share the same triple-nested (lm, u, v) loop shape and, per stage,
// always process exactly n/2 butterflies regardless of stage or direction
// (m*ht = hm*t = n/2 always) -- this lets one address generator drive both
// modes via a small set of mode-muxed formulas (see inner_count/stride/
// outer below) rather than two separate control paths.
//
// ---- Revision 2: batched twiddle reuse (see NTT_ACCEL_DESIGN.md's "#1"
// section for the burst-DMA attempt this superseded) ----
//
// Revision 1 staged one butterfly's operands as a word-at-a-time
// read-modify-write into the shared 25x64b Keccak state array, and issued
// one single-outstanding req/gnt/valid DRAM transaction per word -- safe
// and simple, but the dominant cost, confirmed (not assumed) by
// ntt_hw_cost_breakdown.c: 87% of a single NTT call's cycles were the
// per-word round-trip latency inside this FSM.
//
// A wide (16-lane) AXI CACHE_LINE_REQ burst was attempted here to attack
// that latency directly, but was abandoned: axi_adapter.sv's burst
// (type_i != SINGLE_REQ) read path unconditionally zeroes the low
// CACHELINE_BYTE_OFFSET address bits (see its ar.addr masking), because
// it was built for CVA6's own dcache/icache fixed-alignment cache-line
// fetches, not arbitrary-offset block transfers -- our batch base
// addresses (k1_base/k2_base) are not generally aligned to that boundary,
// so a burst read could silently return data from the wrong address (this
// was caught on real RTL simulation, not assumed). Reworking the
// batching scheme to force alignment, or replacing axi_adapter reuse with
// a genuinely dedicated burst master, were both judged not worth the
// added complexity/area for the uncertain remaining benefit.
//
// What this revision KEEPS from that work, because it stands on its own
// merit independent of burst DMA: batching up to 16 CONSECUTIVE v's for a
// SINGLE u (not spanning twiddle groups, unlike revision 1's independent-
// triple batching) so the (now-shared, once-per-batch) twiddle value is
// fetched once instead of once per butterfly -- still single-outstanding,
// single-word DRAM transactions per a[] word, but up to 16x fewer twiddle
// round trips per stage. Compute operates directly on dedicated
// k1_batch_q/k2_batch_q registers (results overwrite them in place),
// eliminating the read-modify-write scatter/gather dance revision 1
// needed to stage through the shared Keccak array.
//
module ntt_engine #(
    parameter int unsigned AXI_ADDR_WIDTH = 64,
    parameter int unsigned AXI_DATA_WIDTH = 64
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,

    // job descriptor, read from the register file
    input  logic                        job_go_i,
    input  logic [AXI_ADDR_WIDTH-1:0]   job_a_addr_i,
    input  logic [AXI_ADDR_WIDTH-1:0]   job_gm_addr_i,
    input  logic [4:0]                  job_logn_i,
    input  logic [31:0]                 job_p_val_i,       // modulus p
    input  logic [31:0]                 job_p0i_val_i,      // p0i = -1/p mod 2^32
    // direction: 0 = forward (mp_NTT), 1 = inverse (mp_iNTT).
    input  logic                        job_mode_i,
    // inverse-mode scaling convention (ignored when job_mode_i=0): 0 =
    // Falcon convention (distribute n^-1 via mp_half at every butterfly of
    // every stage, see mp_iNTT below); 1 = ML-DSA convention (no per-stage
    // scaling -- software applies its own single final correction multiply,
    // matching invntt_tomont()'s plain sum-then-multiply-by-zeta butterfly).
    input  logic                        job_noscale_i,

    // job status, latched until software clears NTT_CTRL.GO
    output logic                        job_done_o,

    // simple single-outstanding memory-like master port (a[]/gm[] in DRAM)
    output logic                        mem_req_o,
    output logic [AXI_ADDR_WIDTH-1:0]   mem_addr_o,
    output logic                        mem_we_o,
    output logic [AXI_DATA_WIDTH-1:0]   mem_wdata_o,
    output logic [AXI_DATA_WIDTH/8-1:0] mem_be_o,
    input  logic                        mem_gnt_i,
    input  logic                        mem_valid_i,
    input  logic [AXI_DATA_WIDTH-1:0]   mem_rdata_i,

    // 1 whenever a job is in progress (for external mem-port arbitration)
    output logic                        busy_o
);

  typedef enum logic [3:0] {
    IDLE,
    BATCH_INIT,
    LOAD_TWID_REQ,
    LOAD_TWID_WAIT,
    LOAD_K1_REQ,
    LOAD_K1_WAIT,
    LOAD_K2_REQ,
    LOAD_K2_WAIT,
    MM_STEP,
    WB_K1_REQ,
    WB_K1_WAIT,
    WB_K2_REQ,
    WB_K2_WAIT,
    BATCH_ADVANCE,
    DONE_HOLD
  } state_e;

  state_e state_q, state_d;

  logic                      job_go_old_q;

  // latched job parameters
  logic [AXI_ADDR_WIDTH-1:0] a_addr_q, a_addr_d;
  logic [AXI_ADDR_WIDTH-1:0] gm_addr_q, gm_addr_d;
  logic [4:0]                logn_q, logn_d;
  logic [31:0]                p_q, p_d;
  logic [31:0]                p0i_q, p0i_d;
  logic                      mode_q, mode_d;
  logic                      noscale_q, noscale_d;

  // NTT address-generator state (see mp_NTT/mp_iNTT loop shape in the
  // header comment). t_q/outer_q evolve in opposite directions per mode:
  //   NTT:  t starts at n, halves per stage; outer(m) starts at 1, doubles.
  //   iNTT: t starts at 1, doubles per stage; outer(hm) starts at n/2, halves.
  logic [31:0] n_q, n_d;
  logic [31:0] t_q, t_d;
  logic [31:0] outer_q, outer_d;
  logic [31:0] v0_q, v0_d;
  logic [31:0] u_q, u_d;
  logic [31:0] v_q, v_d;
  logic [4:0]  lm_q, lm_d;
  logic [31:0] stage_bf_left_q, stage_bf_left_d;  // butterflies left in the current stage, as of this batch's start

  // batch state -- a batch is up to 16 consecutive v's for the CURRENT u,
  // sharing a single twiddle fetch. Loads/stores are still single-word,
  // single-outstanding DRAM transactions (see header comment). Widened to
  // 64 bits so the same registers can hold a 32-bit NTT modular value
  // (low half only).
  logic [31:0] k1_base_q, k1_base_d;   // a[] index of this batch's first k1
  logic [31:0] twiddle_q, twiddle_d;   // single twiddle, shared by the whole batch
  logic [4:0]  batch_count_q, batch_count_d; // 1..16, entries this batch actually has
  logic [3:0]  triple_idx_q, triple_idx_d;   // 0..15, reused as the active index across LOAD/COMPUTE/WB phases
  logic [63:0] k1_batch_q  [0:15], k1_batch_d  [0:15];
  logic [63:0] k2_batch_q  [0:15], k2_batch_d  [0:15];

  // multiply-reduce pipeline (single shared multiplier, reused 3x per
  // butterfly).
  logic [1:0]  mm_cyc_q, mm_cyc_d;
  logic [63:0] z_q, z_d;      // Montgomery z
  logic [31:0] w_q, w_d;      // Montgomery w
  logic [63:0] sum_q, sum_d;  // Montgomery sum

  logic job_go_rise;
  assign job_go_rise = job_go_i & ~job_go_old_q;

  assign busy_o = (state_q != IDLE) && (state_q != DONE_HOLD);

  // ---- per-stage derived quantities (mode-muxed, see header comment) --
  logic [31:0] inner_count;  // NTT: ht = t>>1 ; iNTT: t
  logic [31:0] stride;       // NTT: t         ; iNTT: dt = t<<1
  assign inner_count = mode_q ? t_q        : (t_q >> 1);
  assign stride       = mode_q ? (t_q << 1) : t_q;

  logic [31:0] twiddle_idx;
  logic [31:0] k2_base;
  assign twiddle_idx = u_q + outer_q;
  assign k2_base       = k1_base_q + inner_count;

  // ---- modular arithmetic helpers (mirror ng_inner.h exactly) ---------
  function automatic logic [31:0] cond_addback(input logic [31:0] d, input logic [31:0] p);
    cond_addback = d + (d[31] ? p : 32'd0);
  endfunction

  function automatic logic [31:0] mp_add_f(input logic [31:0] a, input logic [31:0] b, input logic [31:0] p);
    mp_add_f = cond_addback(a + b - p, p);
  endfunction

  function automatic logic [31:0] mp_sub_f(input logic [31:0] a, input logic [31:0] b, input logic [31:0] p);
    mp_sub_f = cond_addback(a - b, p);
  endfunction

  function automatic logic [31:0] mp_half_f(input logic [31:0] a, input logic [31:0] p);
    logic [31:0] t;
    t = a + (a[0] ? p : 32'd0);
    mp_half_f = t >> 1;
  endfunction

  // ---- current triple's operands (combinational; stable for the whole
  // MM_STEP sequence, since the result write only lands in k1_batch_q/
  // k2_batch_q on the clock edge after MM_STEP's last cycle) ------------
  logic [31:0] cur_x1, cur_x2, cur_s;
  assign cur_x1 = k1_batch_q[triple_idx_q][31:0];
  assign cur_x2 = k2_batch_q[triple_idx_q][31:0];
  assign cur_s  = twiddle_q;

  logic [31:0] mulA;
  assign mulA = mode_q ? mp_sub_f(cur_x1, cur_x2, p_q) : cur_x2;

  // ---- shared multiplier: 32x32->64 unsigned, Montgomery reduction -----
  logic signed [63:0] mm_opA, mm_opB;
  logic signed [127:0] mm_prod;
  always_comb begin
    unique case (mm_cyc_q)
      2'd0:    begin mm_opA = {32'b0, mulA};     mm_opB = {32'b0, cur_s};  end
      2'd1:    begin mm_opA = {32'b0, z_q[31:0]}; mm_opB = {32'b0, p0i_q}; end
      default: begin mm_opA = {32'b0, w_q};       mm_opB = {32'b0, p_q};   end
    endcase
  end
  assign mm_prod = mm_opA * mm_opB;

  logic [31:0] mont_result;
  assign mont_result = cond_addback(sum_q[63:32] - p_q, p_q);

  // ---- DRAM byte addresses for this batch. a[]/gm[] are uint32_t arrays
  // (<<2) ------------------------------------------------------------------
  logic [AXI_ADDR_WIDTH-1:0] twid_addr;
  assign twid_addr = gm_addr_q + (AXI_ADDR_WIDTH'(twiddle_idx) << 2);

  logic [AXI_ADDR_WIDTH-1:0] k1_base_byte_addr, k2_base_byte_addr;
  assign k1_base_byte_addr = a_addr_q + (AXI_ADDR_WIDTH'(k1_base_q) << 2);
  assign k2_base_byte_addr = a_addr_q + (AXI_ADDR_WIDTH'(k2_base)   << 2);

  // per-triple word address, used for both LOAD and WB loops
  logic [AXI_ADDR_WIDTH-1:0] k1_word_addr, k2_word_addr;
  assign k1_word_addr = k1_base_byte_addr + (AXI_ADDR_WIDTH'(triple_idx_q) << 2);
  assign k2_word_addr = k2_base_byte_addr + (AXI_ADDR_WIDTH'(triple_idx_q) << 2);

  always_comb begin
    // defaults
    state_d         = state_q;
    a_addr_d        = a_addr_q;
    gm_addr_d       = gm_addr_q;
    logn_d          = logn_q;
    p_d             = p_q;
    p0i_d           = p0i_q;
    mode_d          = mode_q;
    noscale_d       = noscale_q;
    n_d             = n_q;
    t_d             = t_q;
    outer_d         = outer_q;
    v0_d            = v0_q;
    u_d             = u_q;
    v_d             = v_q;
    lm_d            = lm_q;
    stage_bf_left_d = stage_bf_left_q;
    k1_base_d       = k1_base_q;
    twiddle_d       = twiddle_q;
    batch_count_d   = batch_count_q;
    triple_idx_d    = triple_idx_q;
    k1_batch_d      = k1_batch_q;
    k2_batch_d      = k2_batch_q;
    mm_cyc_d        = mm_cyc_q;
    z_d             = z_q;
    w_d             = w_q;
    sum_d           = sum_q;

    job_done_o  = 1'b0;
    mem_req_o   = 1'b0;
    mem_addr_o  = '0;
    mem_we_o    = 1'b0;
    mem_wdata_o = '0;
    mem_be_o    = '0;

    unique case (state_q)
      IDLE: begin
        if (job_go_rise) begin
          a_addr_d    = job_a_addr_i;
          gm_addr_d   = job_gm_addr_i;
          logn_d      = job_logn_i;
          p_d         = job_p_val_i;
          p0i_d       = job_p0i_val_i;
          mode_d      = job_mode_i;
          noscale_d   = job_noscale_i;
          n_d         = 32'd1 << job_logn_i;

          if (job_logn_i == 5'd0) begin
            // mp_NTT/mp_iNTT are no-ops for logn==0
            state_d = DONE_HOLD;
          end else begin
            lm_d = 5'd0;
            if (job_mode_i) begin
              t_d     = 32'd1;
              outer_d = (32'd1 << job_logn_i) >> 1;  // iNTT: hm starts at n/2
            end else begin
              t_d     = 32'd1 << job_logn_i;
              outer_d = 32'd1;                       // NTT: m starts at 1
            end
            v0_d            = 32'd0;
            u_d             = 32'd0;
            v_d             = 32'd0;
            stage_bf_left_d = (32'd1 << job_logn_i) >> 1;
            state_d         = BATCH_INIT;
          end
        end
      end

      // One cycle after any point where v0_q/v_q/u_q/t_q/outer_q were
      // updated (IDLE's job start, or BATCH_ADVANCE's same-stage-continue
      // or next-stage transition) -- deferred by exactly one cycle so
      // `inner_count` here reflects the just-latched t_q, not a stale
      // value from before the transition.
      BATCH_INIT: begin
        logic [31:0] remaining;
        remaining = inner_count - v_q;
        k1_base_d = v0_q + v_q;
        if (remaining >= 32'd16) begin
          batch_count_d = 5'd16;
        end else begin
          batch_count_d = remaining[4:0];
        end
        triple_idx_d = 4'd0;
        state_d = LOAD_TWID_REQ;
      end

      LOAD_TWID_REQ: begin
        mem_req_o  = 1'b1;
        mem_we_o   = 1'b0;
        mem_addr_o = twid_addr;
        mem_be_o   = twid_addr[2] ? 8'hF0 : 8'h0F;
        if (mem_gnt_i) begin
          state_d = LOAD_TWID_WAIT;
        end
      end

      LOAD_TWID_WAIT: begin
        if (mem_valid_i) begin
          twiddle_d = twid_addr[2] ? mem_rdata_i[63:32] : mem_rdata_i[31:0];
          state_d   = LOAD_K1_REQ;
        end
      end

      LOAD_K1_REQ: begin
        mem_req_o  = 1'b1;
        mem_we_o   = 1'b0;
        mem_addr_o = k1_word_addr;
        mem_be_o   = k1_word_addr[2] ? 8'hF0 : 8'h0F;
        if (mem_gnt_i) begin
          state_d = LOAD_K1_WAIT;
        end
      end

      LOAD_K1_WAIT: begin
        if (mem_valid_i) begin
          k1_batch_d[triple_idx_q][31:0] = k1_word_addr[2] ? mem_rdata_i[63:32] : mem_rdata_i[31:0];
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            state_d      = LOAD_K2_REQ;
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = LOAD_K1_REQ;
          end
        end
      end

      LOAD_K2_REQ: begin
        mem_req_o  = 1'b1;
        mem_we_o   = 1'b0;
        mem_addr_o = k2_word_addr;
        mem_be_o   = k2_word_addr[2] ? 8'hF0 : 8'h0F;
        if (mem_gnt_i) begin
          state_d = LOAD_K2_WAIT;
        end
      end

      LOAD_K2_WAIT: begin
        if (mem_valid_i) begin
          k2_batch_d[triple_idx_q][31:0] = k2_word_addr[2] ? mem_rdata_i[63:32] : mem_rdata_i[31:0];
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            mm_cyc_d     = 2'd0;
            state_d      = MM_STEP;
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = LOAD_K2_REQ;
          end
        end
      end

      MM_STEP: begin
        unique case (mm_cyc_q)
          2'd0: begin
            z_d      = mm_prod[63:0];
            mm_cyc_d = 2'd1;
          end
          2'd1: begin
            w_d      = mm_prod[31:0];
            mm_cyc_d = 2'd2;
          end
          2'd2: begin
            sum_d    = z_q + mm_prod[63:0];
            mm_cyc_d = 2'd3;
          end
          default: begin
            // mont_result is combinational from the registers latched
            // over the last 3 cycles.
            if (mode_q) begin
              // Falcon convention distributes n^-1 via mp_half at every
              // butterfly (ng_mp31.c mp_iNTT); ML-DSA convention (NOSCALE)
              // does a plain sum here and leaves all scaling to a single
              // final software-side multiply (invntt_tomont()).
              k1_batch_d[triple_idx_q][31:0] = noscale_q
                  ? mp_add_f(cur_x1, cur_x2, p_q)
                  : mp_half_f(mp_add_f(cur_x1, cur_x2, p_q), p_q);
              k2_batch_d[triple_idx_q][31:0] = mont_result;
            end else begin
              k1_batch_d[triple_idx_q][31:0] = mp_add_f(cur_x1, mont_result, p_q);
              k2_batch_d[triple_idx_q][31:0] = mp_sub_f(cur_x1, mont_result, p_q);
            end

            if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
              triple_idx_d = 4'd0;
              state_d      = WB_K1_REQ;
            end else begin
              triple_idx_d = triple_idx_q + 4'd1;
              mm_cyc_d     = 2'd0;
              state_d      = MM_STEP;
            end
          end
        endcase
      end

      WB_K1_REQ: begin
        mem_req_o   = 1'b1;
        mem_we_o    = 1'b1;
        mem_addr_o  = k1_word_addr;
        mem_wdata_o = k1_word_addr[2] ? {k1_batch_q[triple_idx_q][31:0], 32'h0} : {32'h0, k1_batch_q[triple_idx_q][31:0]};
        mem_be_o    = k1_word_addr[2] ? 8'hF0 : 8'h0F;
        if (mem_gnt_i) begin
          state_d = WB_K1_WAIT;
        end
      end

      WB_K1_WAIT: begin
        if (mem_valid_i) begin
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            state_d      = WB_K2_REQ;
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = WB_K1_REQ;
          end
        end
      end

      WB_K2_REQ: begin
        mem_req_o   = 1'b1;
        mem_we_o    = 1'b1;
        mem_addr_o  = k2_word_addr;
        mem_wdata_o = k2_word_addr[2] ? {k2_batch_q[triple_idx_q][31:0], 32'h0} : {32'h0, k2_batch_q[triple_idx_q][31:0]};
        mem_be_o    = k2_word_addr[2] ? 8'hF0 : 8'h0F;
        if (mem_gnt_i) begin
          state_d = WB_K2_WAIT;
        end
      end

      WB_K2_WAIT: begin
        if (mem_valid_i) begin
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            state_d      = BATCH_ADVANCE;
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = WB_K2_REQ;
          end
        end
      end

      BATCH_ADVANCE: begin
        logic [31:0] stage_left_after;
        logic [4:0]  new_lm;
        logic [31:0] v_next;
        stage_left_after = stage_bf_left_q - {27'b0, batch_count_q};
        new_lm            = lm_q + 5'd1;
        v_next            = v_q + {27'b0, batch_count_q};

        if (stage_left_after == 32'd0) begin
          if (new_lm == logn_q) begin
            state_d = DONE_HOLD;
          end else begin
            if (mode_q) begin
              t_d     = t_q << 1;
              outer_d = outer_q >> 1;
            end else begin
              t_d     = t_q >> 1;
              outer_d = outer_q << 1;
            end
            lm_d            = new_lm;
            v0_d            = 32'd0;
            u_d             = 32'd0;
            v_d             = 32'd0;
            stage_bf_left_d = n_q >> 1;
            state_d         = BATCH_INIT;
          end
        end else begin
          stage_bf_left_d = stage_left_after;
          if (v_next == inner_count) begin
            v_d  = 32'd0;
            u_d  = u_q + 32'd1;
            v0_d = v0_q + stride;
          end else begin
            v_d = v_next;
          end
          state_d = BATCH_INIT;
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
      state_q         <= IDLE;
      job_go_old_q    <= 1'b0;
      a_addr_q        <= '0;
      gm_addr_q       <= '0;
      logn_q          <= '0;
      p_q             <= '0;
      p0i_q           <= '0;
      mode_q          <= 1'b0;
      noscale_q       <= 1'b0;
      n_q             <= '0;
      t_q             <= '0;
      outer_q         <= '0;
      v0_q            <= '0;
      u_q             <= '0;
      v_q             <= '0;
      lm_q            <= '0;
      stage_bf_left_q <= '0;
      k1_base_q       <= '0;
      twiddle_q       <= '0;
      batch_count_q   <= '0;
      triple_idx_q    <= '0;
      mm_cyc_q        <= '0;
      z_q             <= '0;
      w_q             <= '0;
      sum_q           <= '0;
      for (int i = 0; i < 16; i++) begin
        k1_batch_q[i]  <= '0;
        k2_batch_q[i]  <= '0;
      end
    end else begin
      state_q         <= state_d;
      job_go_old_q    <= job_go_i;
      a_addr_q        <= a_addr_d;
      gm_addr_q       <= gm_addr_d;
      logn_q          <= logn_d;
      p_q             <= p_d;
      p0i_q           <= p0i_d;
      mode_q          <= mode_d;
      noscale_q       <= noscale_d;
      n_q             <= n_d;
      t_q             <= t_d;
      outer_q         <= outer_d;
      v0_q            <= v0_d;
      u_q             <= u_d;
      v_q             <= v_d;
      lm_q            <= lm_d;
      stage_bf_left_q <= stage_bf_left_d;
      k1_base_q       <= k1_base_d;
      twiddle_q       <= twiddle_d;
      batch_count_q   <= batch_count_d;
      triple_idx_q    <= triple_idx_d;
      mm_cyc_q        <= mm_cyc_d;
      z_q             <= z_d;
      w_q             <= w_d;
      sum_q           <= sum_d;
      k1_batch_q      <= k1_batch_d;
      k2_batch_q      <= k2_batch_d;
    end
  end

endmodule : ntt_engine
