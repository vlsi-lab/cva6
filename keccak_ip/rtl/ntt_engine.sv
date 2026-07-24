//
// ntt_engine: hardware offload of HAWK's mp_NTT()/mp_iNTT() (ng_mp31.c,
// non-AVX2 path -- the one CVA6 actually compiles), the shared primitive
// kernel behind solve_NTRU() (KeyGen's 80% bottleneck) and vrfy_ntt_norm()
// (Verify's 76% bottleneck), plus mp_NTT_autoadj's reduced-butterfly phase
// (hawk_vrfy.c), plus (Revision 3) vect_FFT()/vect_iFFT() (ng_fxp.c), the
// fixed-point transform behind solve_NTRU_intermediate()'s babai_loop --
// see NTT_ACCEL_DESIGN.md for the profiling and scoping rationale for all
// three.
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
//
// Both share the same triple-nested (lm, u, v) loop shape and, per stage,
// always process exactly n/2 butterflies regardless of stage or direction
// (m*ht = hm*t = n/2 always) -- this lets one address generator drive both
// modes via a small set of mode-muxed formulas (see inner_count/stride/
// outer below) rather than two separate control paths.
//
// A third mode (job_mode_i[1:0]==2'b10) serves mp_NTT_autoadj's
// (hawk_vrfy.c) "reduced butterfly" phase -- NOT the whole function.
// mp_NTT_autoadj has two parts: an O(n/4) "unfold" step (single twiddle
// gm[1], reflected a[u]/a[hn-u] indexing) that this engine does not
// implement and stays software-only, followed by a butterfly loop that is
// *almost* identical to plain mp_NTT run on an (n/2)-element array, except
// it only visits half as many `u` values per stage (m>>1, not m) while the
// twiddle offset stays the full m. Because this engine's per-stage
// butterfly count (stage_bf_left_q, always n_q>>1) already determines how
// many `u` values get visited -- not a separately-tracked loop bound --
// the (m>>1)-vs-m distinction turns out to require no new address-
// generator logic at all: calling this engine with
// job_logn_i=(autoadj's logn - 1) (making n_q equal autoadj's hn
// automatically) and starting outer_q at 2 instead of 1 (mode_i[1])
// reproduces the reduced loop exactly. See NTT_ACCEL_DESIGN.md for the
// full derivation.
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
// ---- Revision 3: vect_FFT()/vect_iFFT() (fixed-point FFT/iFFT), sharing
// this engine rather than a new one (see NTT_ACCEL_DESIGN.md's "Fixed-
// point FFT scoping" section for the derivation) ----
//
// job_mode_i[2] selects the FFT family (fixed-point, ng_fxp.c) instead of
// the NTT family (modular, ng_mp31.c). The two turn out to share almost
// everything:
//
//   - Address generator: vect_FFT's (lm, i, j) loop is the SAME shape as
//     mp_NTT_autoadj's (lm, u, v) loop -- both visit m>>1 values of the
//     outer index per stage (not m) while the twiddle offset stays the
//     full m (GM_TAB[m+i] / gm[u+m]). vect_FFT even starts at lm=1
//     (skipping lm=0) exactly like the autoadj mapping's job_logn_i =
//     (real logn - 1) trick already does. So FFT-forward reuses that
//     SAME trick (outer_q starts at 2, via job_mode_i[2] now also
//     triggering it, not just job_mode_i[1]) with zero new address-
//     generator logic. vect_iFFT mirrors this the way mp_iNTT mirrors
//     mp_NTT, needing one more tweak: its outer_q must start at the full
//     n_q (not n_q>>1 like iNTT), because iFFT's real m-sequence is
//     hn,hn/2,...,2 (not hn/2,hn/4,...,1) -- see job_mode_i[2] gating
//     outer_d's IDLE-state initial value below. The per-stage t_q/outer_q
//     EVOLUTION (halving/doubling each stage) is identical across all
//     four families and needed no changes at all.
//
//   - Per-butterfly arithmetic is genuinely new: fxc_add/fxc_sub (two
//     independent 64-bit adds/subs, real and imaginary parts) replace
//     mp_add_f/mp_sub_f, and fxc_mul (a length-3 Karatsuba complex
//     multiply: z0=fxr_mul(a.re,b.re), z1=fxr_mul(a.im,b.im),
//     z2=fxr_mul(a.re+a.im,b.re+b.im), result=(z0-z1, z2-z0-z1)) replaces
//     mp_montymul -- still "one multiplier reused 3x per butterfly",
//     just with different per-cycle operands and a different combine
//     formula, so the existing mm_cyc_q 4-cycle pipeline (0,1,2,default)
//     is reused as-is with mode-muxed operand selection. iFFT additionally
//     halves (fxr_half, i.e. round-to-nearest >>1) both z1's real/imag sum
//     AND the pre-multiply operand (fxc_half(fxc_sub(x,y)), not just the
//     sum like mp_iNTT does) -- ng_fxp.c has no per-call precomputed
//     "twiddle/2" table (GM_TAB is fixed, see below) to absorb that the
//     way igm[] does for mp_iNTT, so it's explicit here.
//
//   - The multiplier itself widens from 32x32->64 (Montgomery, mod-p
//     values) to a shared 64x64->128 signed multiplier (fxr is a 64-bit
//     Q32.32 fixed-point value, ng_inner.h). NTT-family operands are
//     zero-extended into the wider operand slots -- since they're always
//     non-negative and well under 2^62, the product's low 64 bits are
//     bit-for-bit identical to the old narrower multiply, so NTT-mode
//     behavior is provably unaffected by the width change.
//
//   - Twiddle storage is the OPPOSITE tradeoff from NTT's gm[]/igm[]:
//     GM_TAB (ng_fxp.c) is a FIXED, modulus-independent constant table
//     (roots of unity, generated once, never recomputed per job) rather
//     than something mp_mkgm/mp_mkgmigm regenerates per call for whatever
//     prime is in use. That makes it a ROM candidate instead of a DRAM
//     fetch -- see fft_gm_rom.sv (bit-exact extraction of GM_TAB[1024]).
//     BATCH_INIT reads it combinationally (twiddle_idx is already stable
//     there) and skips LOAD_TWID_REQ/WAIT entirely for FFT-family jobs,
//     trading a DRAM round trip for a same-cycle ROM read.
//
//   - Data layout: fxr is 64 bits (the full AXI_DATA_WIDTH already, unlike
//     NTT's 32-bit words), so FFT-family loads/stores use the whole bus
//     with no addr[2] half-select. But each butterfly operand is now a
//     COMPLEX pair (re, im) rather than one modular value, and the
//     imaginary half of the source array lives at a fixed offset (+n_q
//     fxr-words, i.e. +n_q*8 bytes) from the real half within the SAME
//     software array -- not a separate DRAM region like gm[]/igm[]. This
//     doubles both the per-triple register footprint (k1i_batch_q/
//     k2i_batch_q alongside k1_batch_q/k2_batch_q, now fxr-wide) and the
//     FSM's load/writeback state count (LOAD_K1IM_*/LOAD_K2IM_*/
//     WB_K1IM_*/WB_K2IM_*, structurally identical to the existing
//     K1/K2 states, inserted right after them and active only when
//     job_mode_i[2]=1 -- the real-part states themselves are untouched by
//     this addition beyond the address-stride and half-select muxing they
//     already needed).
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
    input  logic [31:0]                 job_p_val_i,       // modulus p (NTT family only)
    input  logic [31:0]                 job_p0i_val_i,      // p0i = -1/p mod 2^32 (NTT family only)
    // job_mode_i[0]: direction, 0 = forward-shaped, 1 = inverse.
    // job_mode_i[1]: NTT-family autoadj-reduced-phase variant (only
    // meaningful when bit2=0, bit0=0). job_mode_i[2]: family, 0 = NTT
    // (modular, ng_mp31.c), 1 = fixed-point FFT (ng_fxp.c) -- see the
    // header comment's Revision 3 section. Encoding: 3'b000=mp_NTT,
    // 3'b001=mp_iNTT, 3'b010=mp_NTT_autoadj reduced phase, 3'b100=vect_FFT,
    // 3'b101=vect_iFFT.
    input  logic [2:0]                  job_mode_i,

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

  typedef enum logic [4:0] {
    IDLE,
    BATCH_INIT,
    LOAD_TWID_REQ,
    LOAD_TWID_WAIT,
    LOAD_K1_REQ,
    LOAD_K1_WAIT,
    LOAD_K1IM_REQ,
    LOAD_K1IM_WAIT,
    LOAD_K2_REQ,
    LOAD_K2_WAIT,
    LOAD_K2IM_REQ,
    LOAD_K2IM_WAIT,
    MM_STEP,
    WB_K1_REQ,
    WB_K1_WAIT,
    WB_K1IM_REQ,
    WB_K1IM_WAIT,
    WB_K2_REQ,
    WB_K2_WAIT,
    WB_K2IM_REQ,
    WB_K2IM_WAIT,
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
  logic [2:0]                mode_q, mode_d;

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
  // 64 bits so the same registers hold either a 32-bit NTT modular value
  // (low half only) or a full 64-bit fxr (FFT family); k1i_batch_q/
  // k2i_batch_q hold the imaginary halves and are unused (stay zero) for
  // NTT-family jobs.
  logic [31:0] k1_base_q, k1_base_d;   // a[] index of this batch's first k1
  logic [31:0] twiddle_q, twiddle_d;   // NTT-family: single twiddle, shared by the whole batch
  logic [63:0] tw_re_q, tw_re_d;       // FFT-family: twiddle real part (from ROM, latched at BATCH_INIT)
  logic [63:0] tw_im_q, tw_im_d;       // FFT-family: twiddle imag part (raw, not yet conjugated)
  logic [4:0]  batch_count_q, batch_count_d; // 1..16, entries this batch actually has
  logic [3:0]  triple_idx_q, triple_idx_d;   // 0..15, reused as the active index across LOAD/COMPUTE/WB phases
  logic [63:0] k1_batch_q  [0:15], k1_batch_d  [0:15]; // real (NTT: only value)
  logic [63:0] k2_batch_q  [0:15], k2_batch_d  [0:15];
  logic [63:0] k1i_batch_q [0:15], k1i_batch_d [0:15]; // imaginary (FFT family only)
  logic [63:0] k2i_batch_q [0:15], k2i_batch_d [0:15];

  // multiply-reduce pipeline (single shared multiplier, reused 3x per
  // butterfly for both families -- see header comment's Revision 3
  // section for why the operand width grew from 32x32->64 to 64x64->128
  // without changing NTT-family behavior).
  logic [1:0]  mm_cyc_q, mm_cyc_d;
  logic [63:0] z_q, z_d;      // NTT: Montgomery z ; FFT: unused
  logic [31:0] w_q, w_d;      // NTT: Montgomery w  ; FFT: unused
  logic [63:0] sum_q, sum_d;  // NTT: Montgomery sum; FFT: unused
  logic [63:0] fz0_q, fz0_d;  // FFT: fxc_mul's z0 ; NTT: unused
  logic [63:0] fz1_q, fz1_d;  // FFT: fxc_mul's z1 ; NTT: unused
  logic [63:0] fz2_q, fz2_d;  // FFT: fxc_mul's z2 ; NTT: unused

  logic job_go_rise;
  assign job_go_rise = job_go_i & ~job_go_old_q;

  assign busy_o = (state_q != IDLE) && (state_q != DONE_HOLD);

  // ---- per-stage derived quantities (mode-muxed, see header comment) --
  logic [31:0] inner_count;  // NTT/autoadj/FFT-fwd: ht = t>>1 ; iNTT/iFFT: t
  logic [31:0] stride;       // NTT/autoadj/FFT-fwd: t         ; iNTT/iFFT: dt = t<<1
  assign inner_count = mode_q[0] ? t_q        : (t_q >> 1);
  assign stride       = mode_q[0] ? (t_q << 1) : t_q;

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

  // fxr_half (ng_inner.h's fxr_div2e(x,1)): round-to-nearest arithmetic
  // shift right by 1.
  function automatic logic signed [63:0] fxr_half_f(input logic signed [63:0] x);
    fxr_half_f = (x + 64'sd1) >>> 1;
  endfunction

  // ---- current triple's operands (combinational; stable for the whole
  // MM_STEP sequence, since the result write only lands in k1_batch_q/
  // k2_batch_q on the clock edge after MM_STEP's last cycle) ------------
  logic [31:0] cur_x1, cur_x2, cur_s;
  assign cur_x1 = k1_batch_q[triple_idx_q][31:0];
  assign cur_x2 = k2_batch_q[triple_idx_q][31:0];
  assign cur_s  = twiddle_q;

  logic [31:0] mulA;
  assign mulA = mode_q[0] ? mp_sub_f(cur_x1, cur_x2, p_q) : cur_x2;

  logic signed [63:0] cur_x1_re, cur_x1_im, cur_x2_re, cur_x2_im;
  assign cur_x1_re = k1_batch_q[triple_idx_q];
  assign cur_x1_im = k1i_batch_q[triple_idx_q];
  assign cur_x2_re = k2_batch_q[triple_idx_q];
  assign cur_x2_im = k2i_batch_q[triple_idx_q];

  // FFT-family multiply operand: forward uses y (=x2) directly; inverse
  // uses fxc_half(x1-x2) -- see header comment (no precomputed "twiddle/2"
  // table for FFT the way igm[] provides for iNTT, so the half is explicit
  // here).
  logic signed [63:0] mulA_re, mulA_im;
  assign mulA_re = mode_q[0] ? fxr_half_f(cur_x1_re - cur_x2_re) : cur_x2_re;
  assign mulA_im = mode_q[0] ? fxr_half_f(cur_x1_im - cur_x2_im) : cur_x2_im;

  // iFFT uses the conjugated twiddle (im negated); forward FFT does not.
  logic signed [63:0] tw_im_eff;
  assign tw_im_eff = mode_q[0] ? -tw_im_q : tw_im_q;

  // ---- shared multiplier: 64x64->128 signed, muxed operands/results per
  // family (see header comment's Revision 3 section) --------------------
  logic signed [63:0] mm_opA, mm_opB;
  logic signed [127:0] mm_prod;
  always_comb begin
    unique case (mm_cyc_q)
      2'd0: begin
        if (mode_q[2]) begin mm_opA = tw_re_q;             mm_opB = mulA_re; end
        else            begin mm_opA = {32'b0, mulA};       mm_opB = {32'b0, cur_s};  end
      end
      2'd1: begin
        if (mode_q[2]) begin mm_opA = tw_im_eff;            mm_opB = mulA_im; end
        else            begin mm_opA = {32'b0, z_q[31:0]};   mm_opB = {32'b0, p0i_q}; end
      end
      default: begin
        if (mode_q[2]) begin mm_opA = tw_re_q + tw_im_eff;  mm_opB = mulA_re + mulA_im; end
        else            begin mm_opA = {32'b0, w_q};         mm_opB = {32'b0, p_q};   end
      end
    endcase
  end
  assign mm_prod = mm_opA * mm_opB;

  logic [31:0] mont_result;
  assign mont_result = cond_addback(sum_q[63:32] - p_q, p_q);

  logic signed [63:0] fmr_re, fmr_im; // FFT: fxc_mul(twiddle, mulA) result
  assign fmr_re = fz0_q - fz1_q;
  assign fmr_im = fz2_q - fz0_q - fz1_q;

  // ---- GM_TAB ROM (FFT family twiddle, see fft_gm_rom.sv) -------------
  logic [63:0] rom_re, rom_im;
  fft_gm_rom i_fft_gm_rom (
    .addr_i (twiddle_idx[9:0]),
    .re_o   (rom_re),
    .im_o   (rom_im)
  );

  // ---- DRAM byte addresses for this batch. NTT-family: a[]/gm[] are
  // uint32_t arrays (<<2). FFT-family: f[] is an fxr array (<<3), and the
  // imaginary half lives at a fixed +n_q-fxr-word offset within the SAME
  // array (not a separate DRAM region) ------------------------------------
  logic [AXI_ADDR_WIDTH-1:0] twid_addr;
  assign twid_addr = gm_addr_q + (AXI_ADDR_WIDTH'(twiddle_idx) << 2);

  logic [AXI_ADDR_WIDTH-1:0] k1_base_byte_addr, k2_base_byte_addr;
  logic [AXI_ADDR_WIDTH-1:0] k1_im_base_byte_addr, k2_im_base_byte_addr;
  assign k1_base_byte_addr = mode_q[2]
      ? (a_addr_q + (AXI_ADDR_WIDTH'(k1_base_q) << 3))
      : (a_addr_q + (AXI_ADDR_WIDTH'(k1_base_q) << 2));
  assign k2_base_byte_addr = mode_q[2]
      ? (a_addr_q + (AXI_ADDR_WIDTH'(k2_base)   << 3))
      : (a_addr_q + (AXI_ADDR_WIDTH'(k2_base)   << 2));
  assign k1_im_base_byte_addr = a_addr_q + ((AXI_ADDR_WIDTH'(k1_base_q) + AXI_ADDR_WIDTH'(n_q)) << 3);
  assign k2_im_base_byte_addr = a_addr_q + ((AXI_ADDR_WIDTH'(k2_base)   + AXI_ADDR_WIDTH'(n_q)) << 3);

  // per-triple word address, used for both LOAD and WB loops
  logic [AXI_ADDR_WIDTH-1:0] k1_word_addr, k2_word_addr;
  logic [AXI_ADDR_WIDTH-1:0] k1im_word_addr, k2im_word_addr;
  assign k1_word_addr = k1_base_byte_addr
      + (AXI_ADDR_WIDTH'(triple_idx_q) << (mode_q[2] ? 3 : 2));
  assign k2_word_addr = k2_base_byte_addr
      + (AXI_ADDR_WIDTH'(triple_idx_q) << (mode_q[2] ? 3 : 2));
  assign k1im_word_addr = k1_im_base_byte_addr + (AXI_ADDR_WIDTH'(triple_idx_q) << 3);
  assign k2im_word_addr = k2_im_base_byte_addr + (AXI_ADDR_WIDTH'(triple_idx_q) << 3);

  always_comb begin
    // defaults
    state_d         = state_q;
    a_addr_d        = a_addr_q;
    gm_addr_d       = gm_addr_q;
    logn_d          = logn_q;
    p_d             = p_q;
    p0i_d           = p0i_q;
    mode_d          = mode_q;
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
    tw_re_d         = tw_re_q;
    tw_im_d         = tw_im_q;
    batch_count_d   = batch_count_q;
    triple_idx_d    = triple_idx_q;
    k1_batch_d      = k1_batch_q;
    k2_batch_d      = k2_batch_q;
    k1i_batch_d     = k1i_batch_q;
    k2i_batch_d     = k2i_batch_q;
    mm_cyc_d        = mm_cyc_q;
    z_d             = z_q;
    w_d             = w_q;
    sum_d           = sum_q;
    fz0_d           = fz0_q;
    fz1_d           = fz1_q;
    fz2_d           = fz2_q;

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
          n_d         = 32'd1 << job_logn_i;

          if (job_logn_i == 5'd0) begin
            // mp_NTT/mp_iNTT/vect_FFT/vect_iFFT are all no-ops for logn==0
            state_d = DONE_HOLD;
          end else begin
            lm_d = 5'd0;
            if (job_mode_i[0]) begin
              t_d     = 32'd1;
              // iNTT: hm starts at n/2. iFFT (job_mode_i[2]): starts at
              // the full n_q instead -- iFFT's real m-sequence is
              // hn,hn/2,...,2 (not hn/2,hn/4,...,1 like iNTT's hm), see
              // header comment's Revision 3 section.
              outer_d = job_mode_i[2] ? (32'd1 << job_logn_i)
                                       : (32'd1 << job_logn_i) >> 1;
            end else begin
              t_d     = 32'd1 << job_logn_i;
              // autoadj-reduced-phase (mode_i[1]) OR FFT-forward
              // (mode_i[2]) start the twiddle offset at m=2, not m=1 --
              // see the header comment. Plain NTT (mode_i==3'b000) is
              // unaffected.
              outer_d = (job_mode_i[1] || job_mode_i[2]) ? 32'd2 : 32'd1;
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
        if (mode_q[2]) begin
          // FFT family: GM_TAB is a fixed ROM (see header comment) --
          // read it combinationally right here (twiddle_idx is already
          // stable) and skip the DRAM twiddle fetch entirely.
          tw_re_d = rom_re;
          tw_im_d = rom_im;
          state_d = LOAD_K1_REQ;
        end else begin
          state_d = LOAD_TWID_REQ;
        end
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
        mem_be_o   = mode_q[2] ? 8'hFF : (k1_word_addr[2] ? 8'hF0 : 8'h0F);
        if (mem_gnt_i) begin
          state_d = LOAD_K1_WAIT;
        end
      end

      LOAD_K1_WAIT: begin
        if (mem_valid_i) begin
          if (mode_q[2]) begin
            k1_batch_d[triple_idx_q] = mem_rdata_i;
          end else begin
            k1_batch_d[triple_idx_q][31:0] = k1_word_addr[2] ? mem_rdata_i[63:32] : mem_rdata_i[31:0];
          end
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            state_d      = mode_q[2] ? LOAD_K1IM_REQ : LOAD_K2_REQ;
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = LOAD_K1_REQ;
          end
        end
      end

      LOAD_K1IM_REQ: begin
        mem_req_o  = 1'b1;
        mem_we_o   = 1'b0;
        mem_addr_o = k1im_word_addr;
        mem_be_o   = 8'hFF;
        if (mem_gnt_i) begin
          state_d = LOAD_K1IM_WAIT;
        end
      end

      LOAD_K1IM_WAIT: begin
        if (mem_valid_i) begin
          k1i_batch_d[triple_idx_q] = mem_rdata_i;
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            state_d      = LOAD_K2_REQ;
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = LOAD_K1IM_REQ;
          end
        end
      end

      LOAD_K2_REQ: begin
        mem_req_o  = 1'b1;
        mem_we_o   = 1'b0;
        mem_addr_o = k2_word_addr;
        mem_be_o   = mode_q[2] ? 8'hFF : (k2_word_addr[2] ? 8'hF0 : 8'h0F);
        if (mem_gnt_i) begin
          state_d = LOAD_K2_WAIT;
        end
      end

      LOAD_K2_WAIT: begin
        if (mem_valid_i) begin
          if (mode_q[2]) begin
            k2_batch_d[triple_idx_q] = mem_rdata_i;
          end else begin
            k2_batch_d[triple_idx_q][31:0] = k2_word_addr[2] ? mem_rdata_i[63:32] : mem_rdata_i[31:0];
          end
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            if (mode_q[2]) begin
              state_d = LOAD_K2IM_REQ;
            end else begin
              mm_cyc_d = 2'd0;
              state_d  = MM_STEP;
            end
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = LOAD_K2_REQ;
          end
        end
      end

      LOAD_K2IM_REQ: begin
        mem_req_o  = 1'b1;
        mem_we_o   = 1'b0;
        mem_addr_o = k2im_word_addr;
        mem_be_o   = 8'hFF;
        if (mem_gnt_i) begin
          state_d = LOAD_K2IM_WAIT;
        end
      end

      LOAD_K2IM_WAIT: begin
        if (mem_valid_i) begin
          k2i_batch_d[triple_idx_q] = mem_rdata_i;
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            mm_cyc_d     = 2'd0;
            state_d      = MM_STEP;
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = LOAD_K2IM_REQ;
          end
        end
      end

      MM_STEP: begin
        unique case (mm_cyc_q)
          2'd0: begin
            if (mode_q[2]) fz0_d = mm_prod[95:32];
            else            z_d   = mm_prod[63:0];
            mm_cyc_d = 2'd1;
          end
          2'd1: begin
            if (mode_q[2]) fz1_d = mm_prod[95:32];
            else            w_d   = mm_prod[31:0];
            mm_cyc_d = 2'd2;
          end
          2'd2: begin
            if (mode_q[2]) fz2_d = mm_prod[95:32];
            else            sum_d = z_q + mm_prod[63:0];
            mm_cyc_d = 2'd3;
          end
          default: begin
            // mont_result/fmr_re/fmr_im are combinational from the
            // registers latched over the last 3 cycles.
            if (mode_q[2]) begin
              if (mode_q[0]) begin
                // iFFT: z1 = fxc_half(x1+x2) -> k1 ; z2 = fxc_mul(conj(s),
                // fxc_half(x1-x2)) -> k2 (already computed via mulA_re/im
                // and fmr_re/im above).
                k1_batch_d[triple_idx_q]  = fxr_half_f(cur_x1_re + cur_x2_re);
                k1i_batch_d[triple_idx_q] = fxr_half_f(cur_x1_im + cur_x2_im);
                k2_batch_d[triple_idx_q]  = fmr_re;
                k2i_batch_d[triple_idx_q] = fmr_im;
              end else begin
                // FFT forward: z1 = x1 + fxc_mul(s,x2) -> k1 ; z2 = x1 -
                // fxc_mul(s,x2) -> k2.
                k1_batch_d[triple_idx_q]  = cur_x1_re + fmr_re;
                k1i_batch_d[triple_idx_q] = cur_x1_im + fmr_im;
                k2_batch_d[triple_idx_q]  = cur_x1_re - fmr_re;
                k2i_batch_d[triple_idx_q] = cur_x1_im - fmr_im;
              end
            end else begin
              // autoadj-reduced-phase (mode_q==3'b010) uses the same
              // add/sub combination as plain NTT (mode_q[0]==0 either way).
              if (mode_q[0]) begin
                k1_batch_d[triple_idx_q][31:0] = mp_half_f(mp_add_f(cur_x1, cur_x2, p_q), p_q);
                k2_batch_d[triple_idx_q][31:0] = mont_result;
              end else begin
                k1_batch_d[triple_idx_q][31:0] = mp_add_f(cur_x1, mont_result, p_q);
                k2_batch_d[triple_idx_q][31:0] = mp_sub_f(cur_x1, mont_result, p_q);
              end
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
        mem_req_o  = 1'b1;
        mem_we_o   = 1'b1;
        mem_addr_o = k1_word_addr;
        if (mode_q[2]) begin
          mem_wdata_o = k1_batch_q[triple_idx_q];
          mem_be_o    = 8'hFF;
        end else begin
          mem_wdata_o = k1_word_addr[2] ? {k1_batch_q[triple_idx_q][31:0], 32'h0} : {32'h0, k1_batch_q[triple_idx_q][31:0]};
          mem_be_o    = k1_word_addr[2] ? 8'hF0 : 8'h0F;
        end
        if (mem_gnt_i) begin
          state_d = WB_K1_WAIT;
        end
      end

      WB_K1_WAIT: begin
        if (mem_valid_i) begin
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            state_d      = mode_q[2] ? WB_K1IM_REQ : WB_K2_REQ;
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = WB_K1_REQ;
          end
        end
      end

      WB_K1IM_REQ: begin
        mem_req_o   = 1'b1;
        mem_we_o    = 1'b1;
        mem_addr_o  = k1im_word_addr;
        mem_wdata_o = k1i_batch_q[triple_idx_q];
        mem_be_o    = 8'hFF;
        if (mem_gnt_i) begin
          state_d = WB_K1IM_WAIT;
        end
      end

      WB_K1IM_WAIT: begin
        if (mem_valid_i) begin
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            state_d      = WB_K2_REQ;
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = WB_K1IM_REQ;
          end
        end
      end

      WB_K2_REQ: begin
        mem_req_o  = 1'b1;
        mem_we_o   = 1'b1;
        mem_addr_o = k2_word_addr;
        if (mode_q[2]) begin
          mem_wdata_o = k2_batch_q[triple_idx_q];
          mem_be_o    = 8'hFF;
        end else begin
          mem_wdata_o = k2_word_addr[2] ? {k2_batch_q[triple_idx_q][31:0], 32'h0} : {32'h0, k2_batch_q[triple_idx_q][31:0]};
          mem_be_o    = k2_word_addr[2] ? 8'hF0 : 8'h0F;
        end
        if (mem_gnt_i) begin
          state_d = WB_K2_WAIT;
        end
      end

      WB_K2_WAIT: begin
        if (mem_valid_i) begin
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            state_d      = mode_q[2] ? WB_K2IM_REQ : BATCH_ADVANCE;
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = WB_K2_REQ;
          end
        end
      end

      WB_K2IM_REQ: begin
        mem_req_o   = 1'b1;
        mem_we_o    = 1'b1;
        mem_addr_o  = k2im_word_addr;
        mem_wdata_o = k2i_batch_q[triple_idx_q];
        mem_be_o    = 8'hFF;
        if (mem_gnt_i) begin
          state_d = WB_K2IM_WAIT;
        end
      end

      WB_K2IM_WAIT: begin
        if (mem_valid_i) begin
          if (5'(triple_idx_q) + 5'd1 == batch_count_q) begin
            triple_idx_d = 4'd0;
            state_d      = BATCH_ADVANCE;
          end else begin
            triple_idx_d = triple_idx_q + 4'd1;
            state_d      = WB_K2IM_REQ;
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
            // Per-stage t_q/outer_q evolution is identical across all
            // four families (only the IDLE-state initial value differs,
            // see above) -- confirmed by direct derivation against
            // vect_FFT/vect_iFFT's C source, not assumed by analogy.
            if (mode_q[0]) begin
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
      mode_q          <= 3'b0;
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
      tw_re_q         <= '0;
      tw_im_q         <= '0;
      batch_count_q   <= '0;
      triple_idx_q    <= '0;
      mm_cyc_q        <= '0;
      z_q             <= '0;
      w_q             <= '0;
      sum_q           <= '0;
      fz0_q           <= '0;
      fz1_q           <= '0;
      fz2_q           <= '0;
      for (int i = 0; i < 16; i++) begin
        k1_batch_q[i]  <= '0;
        k2_batch_q[i]  <= '0;
        k1i_batch_q[i] <= '0;
        k2i_batch_q[i] <= '0;
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
      tw_re_q         <= tw_re_d;
      tw_im_q         <= tw_im_d;
      batch_count_q   <= batch_count_d;
      triple_idx_q    <= triple_idx_d;
      mm_cyc_q        <= mm_cyc_d;
      z_q             <= z_d;
      w_q             <= w_d;
      sum_q           <= sum_d;
      fz0_q           <= fz0_d;
      fz1_q           <= fz1_d;
      fz2_q           <= fz2_d;
      k1_batch_q      <= k1_batch_d;
      k2_batch_q      <= k2_batch_d;
      k1i_batch_q     <= k1i_batch_d;
      k2i_batch_q     <= k2i_batch_d;
    end
  end

endmodule : ntt_engine
