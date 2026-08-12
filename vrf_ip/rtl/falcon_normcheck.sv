//
// falcon_normcheck: hardware offload of Falcon's Zf(is_short)() (common.c),
// the squared-l2-norm acceptance check run once per verify on the
// recovered (s1,s2) coefficient pair: sum(s1[u]^2) + sum(s2[u]^2),
// compared against a per-degree threshold (l2bound[logn], common.c),
// software-computed and passed in as NORMCHECK_BOUND rather than
// replicated as a hardware table.
//
// Falcon-specific: ML-DSA's poly_chknorm (max-abs early-exit compare) is a
// different ALU op *and* a different reduction shape, not a sum-of-
// squares -- confirmed not shareable with this job (see IMPLEMENTATION.md's
// "Reuse decisions" section). Multiplier reuse with ntt_engine.sv's existing
// Montgomery pipeline was also considered and rejected: this job's
// operands are signed 16-bit coefficients doing a *plain* (unreduced)
// square, entirely unlike ntt_engine.sv's 32-bit Montgomery-domain
// butterfly multiply -- routing this job's much simpler operation through
// that FSM's addressing/control logic would cost more in mux/control
// overhead than a small dedicated 17x17 signed squarer costs on its own.
// Area is kept minimal on this job's own terms instead.
//
// Constant-time note carried over unmodified from the reference: the
// reference accumulates the *entire* sum unconditionally and only applies
// saturation at the very end (`s |= -(ng >> 31)`), rather than early-exit
// once the bound is exceeded, specifically so the run time does not leak
// how far over/under the bound the norm is. This module preserves that
// property: it always walks all n coefficients of both arrays before
// comparing against NORMCHECK_BOUND.
//
// Overflow/saturation: mirrors `ng |= s; ... s |= -(ng >> 31);` exactly,
// simplified to an equivalent single sticky bit. `ng |= s` ORs in every
// bit of s each step, but the only bit of ng the reference ever reads
// back is bit 31 (`ng >> 31`); OR is monotonic, so bit 31 of ng becomes 1
// at the first step where bit 31 of s is 1 and stays 1 forever after --
// exactly what a single sticky flip-flop (`ovf_q`, set once sum's bit 31
// is ever 1, never cleared until the next job) captures. The final
// `s |= -(ng >> 31)` (force s to all-1s once ng's bit 31 has ever been
// set) becomes `ovf_q ? 32'hFFFF_FFFF : sum_q` before the bound compare.
//
module falcon_normcheck #(
    parameter int unsigned AXI_ADDR_WIDTH = 64,
    parameter int unsigned AXI_DATA_WIDTH = 64
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,

    // job descriptor, read from the register file
    input  logic                        job_go_i,
    input  logic [AXI_ADDR_WIDTH-1:0]   job_s1_addr_i,
    input  logic [AXI_ADDR_WIDTH-1:0]   job_s2_addr_i,
    input  logic [31:0]                 job_bound_i,
    input  logic [15:0]                 job_n_i,

    // job status, latched until software clears NORMCHECK_CTRL.GO
    output logic                        job_done_o,
    output logic                        job_pass_o,

    // simple single-outstanding memory-like master port (read-only)
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

  typedef enum logic [2:0] {
    IDLE,
    S1_REQ,
    S1_WAIT,
    S2_REQ,
    S2_WAIT,
    NEXT_U,
    FINISH,
    DONE_HOLD
  } state_e;

  state_e state_q, state_d;

  logic                      job_go_old_q;
  logic [AXI_ADDR_WIDTH-1:0] s1_addr_q, s1_addr_d;
  logic [AXI_ADDR_WIDTH-1:0] s2_addr_q, s2_addr_d;
  logic [31:0]                bound_q, bound_d;
  logic [15:0]                n_q, n_d;
  logic [15:0]                u_q, u_d;

  logic [31:0]                sum_q, sum_d;
  logic                       ovf_q, ovf_d;
  logic                       pass_q, pass_d;

  logic job_go_rise;
  assign job_go_rise = job_go_i & ~job_go_old_q;

  assign busy_o = (state_q != IDLE) && (state_q != DONE_HOLD);

  localparam int unsigned StrbWidth = AXI_DATA_WIDTH / 8;

  // 16-bit-lane read address, shared shape for both s1[]/s2[] (int16_t
  // arrays, matching falcon_decode.sv's output-array addressing)
  logic [AXI_ADDR_WIDTH-1:0] s1_word_addr, s2_word_addr;
  assign s1_word_addr = s1_addr_q + (AXI_ADDR_WIDTH'(u_q) << 1);
  assign s2_word_addr = s2_addr_q + (AXI_ADDR_WIDTH'(u_q) << 1);

  // sign-extend the fetched 16-bit coefficient and square it: z*z as a
  // plain (unreduced) 32-bit product, mirroring `z = s1[u]; s +=
  // (uint32_t)(z * z);` where z is int32_t in the reference.
  function automatic logic [31:0] square_coeff(logic [15:0] lane);
    logic signed [31:0] z;
    z = {{16{lane[15]}}, lane};
    square_coeff = 32'(z * z);
  endfunction

  always_comb begin
    state_d   = state_q;
    s1_addr_d = s1_addr_q;
    s2_addr_d = s2_addr_q;
    bound_d   = bound_q;
    n_d       = n_q;
    u_d       = u_q;
    sum_d     = sum_q;
    ovf_d     = ovf_q;
    pass_d    = pass_q;

    job_done_o = 1'b0;
    job_pass_o = pass_q;

    mem_req_o   = 1'b0;
    mem_addr_o  = '0;
    mem_we_o    = 1'b0;
    mem_wdata_o = '0;
    mem_be_o    = '0;

    unique case (state_q)
      IDLE: begin
        if (job_go_rise) begin
          s1_addr_d = job_s1_addr_i;
          s2_addr_d = job_s2_addr_i;
          bound_d   = job_bound_i;
          n_d       = job_n_i;
          u_d       = 16'd0;
          sum_d     = 32'd0;
          ovf_d     = 1'b0;
          state_d   = (job_n_i == 16'd0) ? FINISH : S1_REQ;
        end
      end

      S1_REQ: begin
        mem_req_o  = 1'b1;
        mem_we_o   = 1'b0;
        mem_addr_o = s1_word_addr;
        mem_be_o   = StrbWidth'(3) << s1_word_addr[2:0];
        if (mem_gnt_i) begin
          state_d = S1_WAIT;
        end
      end

      S1_WAIT: begin
        if (mem_valid_i) begin
          logic [31:0] sum_next;
          sum_next = sum_q + square_coeff(mem_rdata_i[s1_word_addr[2:0]*8 +: 16]);
          sum_d    = sum_next;
          ovf_d    = ovf_q | sum_next[31];
          state_d  = S2_REQ;
        end
      end

      S2_REQ: begin
        mem_req_o  = 1'b1;
        mem_we_o   = 1'b0;
        mem_addr_o = s2_word_addr;
        mem_be_o   = StrbWidth'(3) << s2_word_addr[2:0];
        if (mem_gnt_i) begin
          state_d = S2_WAIT;
        end
      end

      S2_WAIT: begin
        if (mem_valid_i) begin
          logic [31:0] sum_next;
          sum_next = sum_q + square_coeff(mem_rdata_i[s2_word_addr[2:0]*8 +: 16]);
          sum_d    = sum_next;
          ovf_d    = ovf_q | sum_next[31];
          state_d  = NEXT_U;
        end
      end

      NEXT_U: begin
        u_d = u_q + 16'd1;
        state_d = (u_d == n_q) ? FINISH : S1_REQ;
      end

      FINISH: begin
        logic [31:0] sum_sat;
        sum_sat = ovf_q ? 32'hFFFF_FFFF : sum_q;
        pass_d  = (sum_sat <= bound_q);
        state_d = DONE_HOLD;
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
      state_q      <= IDLE;
      job_go_old_q <= 1'b0;
      s1_addr_q    <= '0;
      s2_addr_q    <= '0;
      bound_q      <= '0;
      n_q          <= '0;
      u_q          <= '0;
      sum_q        <= '0;
      ovf_q        <= 1'b0;
      pass_q       <= 1'b0;
    end else begin
      state_q      <= state_d;
      job_go_old_q <= job_go_i;
      s1_addr_q    <= s1_addr_d;
      s2_addr_q    <= s2_addr_d;
      bound_q      <= bound_d;
      n_q          <= n_d;
      u_q          <= u_d;
      sum_q        <= sum_d;
      ovf_q        <= ovf_d;
      pass_q       <= pass_d;
    end
  end

endmodule