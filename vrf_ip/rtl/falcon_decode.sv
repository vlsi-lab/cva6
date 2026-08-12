//
// falcon_decode: hardware offload of Falcon's Zf(comp_decode)() (codec.c),
// the variable-length Golomb-Rice-style signature decompression: each
// coefficient is 1 sign bit + 7 low magnitude bits, followed by a
// unary-coded high part (each `0` bit adds 128 to the magnitude, a `1`
// bit terminates), read as one continuous MSB-first bit stream over the
// input byte array. Falcon-specific: neither ML-DSA (fixed-width packing)
// nor SPHINCS+ (no polynomial encoding at all) has a matching primitive to
// share this with, unlike ntt_engine.sv/rej_sampler.sv/keccak_dma_ctrl.sv.
//
// Algorithm verified bit-for-bit against Zf(comp_decode)() (not
// re-derived from memory): this module implements a generic "read the
// next bit from the continuous stream, fetching a fresh byte from DRAM
// whenever the current byte is exhausted" primitive (BIT_NEED/FETCH_REQ/
// FETCH_WAIT/CONSUME_BIT below) and calls it uniformly 8 times for each
// coefficient's sign+magnitude byte and repeatedly for its unary tail --
// deliberately NOT special-casing the sign+magnitude read as "always a
// fresh byte fetch", because it is not: a coefficient's 8 sign+magnitude
// bits can start mid-byte, combining leftover unconsumed bits from the
// PREVIOUS coefficient's unary tail with fresh bits from a newly fetched
// byte, exactly as Zf(comp_decode)()'s acc/acc_len bookkeeping does.
//
// Malformed-input rejection mirrors the reference exactly: unary run
// magnitude > 2047, forbidden "-0" (sign set, magnitude 0), input stream
// exhausted before a coefficient completes, and nonzero trailing bits in
// the last partially-consumed byte after all N coefficients are decoded.
// DECODE_CTRL.FAIL mirrors Zf(comp_decode)()'s `return 0`; DECODE_CTRL.V
// mirrors its non-zero return value (bytes consumed).
//
// Reads the input stream one byte at a time via the same simple
// single-outstanding memory port every other job on this accelerator
// uses (not word-cached): decompression is a small, bounded-length
// operation relative to NTT/matrix-expansion, and even without reducing
// DRAM transaction count, moving the bit-level shift/mask/compare/branch
// work from software (many RISC-V instructions per bit) into dedicated
// hardware is still a real win -- word-caching was considered and
// deliberately deferred as added complexity for a smaller expected gain
// than it was worth pursuing first.
//
module falcon_decode #(
    parameter int unsigned AXI_ADDR_WIDTH = 64,
    parameter int unsigned AXI_DATA_WIDTH = 64
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,

    // job descriptor, read from the register file
    input  logic                        job_go_i,
    input  logic [AXI_ADDR_WIDTH-1:0]   job_in_addr_i,
    input  logic [AXI_ADDR_WIDTH-1:0]   job_out_addr_i,
    input  logic [15:0]                 job_max_len_i,
    input  logic [15:0]                 job_n_i,

    // job status, latched until software clears DECODE_CTRL.GO
    output logic                        job_done_o,
    output logic                        job_fail_o,
    output logic [15:0]                 job_v_o,

    // simple single-outstanding memory-like master port
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
    NEW_COEF,
    BIT_NEED,
    FETCH_REQ,
    FETCH_WAIT,
    CONSUME_BIT,
    WRITE_REQ,
    WRITE_WAIT,
    TRAIL_CHECK,
    FAIL_STATE,
    DONE_HOLD
  } state_e;

  typedef enum logic { PH_SIGNMAG, PH_UNARY } phase_e;

  state_e state_q, state_d;
  phase_e phase_q, phase_d;

  logic                      job_go_old_q;
  logic [AXI_ADDR_WIDTH-1:0] in_addr_q, in_addr_d;
  logic [AXI_ADDR_WIDTH-1:0] out_addr_q, out_addr_d;
  logic [15:0]               max_len_q, max_len_d;
  logic [15:0]               n_q, n_d;

  logic [15:0]               v_q, v_d;       // bytes consumed so far
  logic [15:0]               u_q, u_d;       // coefficients decoded so far

  logic [7:0]                cur_byte_q, cur_byte_d;
  logic [3:0]                bits_left_q, bits_left_d;  // 0..8, unconsumed bits in cur_byte_q

  logic [7:0]                sm_acc_q, sm_acc_d;   // sign+magnitude byte, assembled bit by bit
  logic [3:0]                sm_cnt_q, sm_cnt_d;    // 0..8, bits assembled into sm_acc_q so far

  logic                      sign_q, sign_d;
  logic [11:0]                mag_q, mag_d;          // magnitude, up to 2047 (+128 headroom before the reject check)

  logic                      fail_q, fail_d;

  logic job_go_rise;
  assign job_go_rise = job_go_i & ~job_go_old_q;

  assign busy_o = (state_q != IDLE) && (state_q != DONE_HOLD);

  localparam int unsigned StrbWidth = AXI_DATA_WIDTH / 8;

  // byte-granular read address for the input stream
  logic [AXI_ADDR_WIDTH-1:0] in_byte_addr;
  assign in_byte_addr = in_addr_q + AXI_ADDR_WIDTH'(v_q);

  // 16-bit-lane write address for the output coefficient array (int16_t x[])
  logic [AXI_ADDR_WIDTH-1:0] out_word_addr;
  assign out_word_addr = out_addr_q + (AXI_ADDR_WIDTH'(u_q) << 1);

  // signed-to-int16 encode: sign_q ? -mag_q : mag_q, mirroring
  // (int16_t)(s ? -(int)m : (int)m) -- mag_q is always <= 2047 here (the
  // >2047 case takes the FAIL_STATE path before this is ever read).
  logic [15:0] coeff_val;
  assign coeff_val = sign_q ? (16'h0 - {4'b0, mag_q}) : {4'b0, mag_q};

  always_comb begin
    state_d      = state_q;
    phase_d      = phase_q;
    in_addr_d    = in_addr_q;
    out_addr_d   = out_addr_q;
    max_len_d    = max_len_q;
    n_d          = n_q;
    v_d          = v_q;
    u_d          = u_q;
    cur_byte_d   = cur_byte_q;
    bits_left_d  = bits_left_q;
    sm_acc_d     = sm_acc_q;
    sm_cnt_d     = sm_cnt_q;
    sign_d       = sign_q;
    mag_d        = mag_q;
    fail_d       = fail_q;

    job_done_o = 1'b0;
    job_fail_o = fail_q;
    job_v_o    = v_q;

    mem_req_o   = 1'b0;
    mem_addr_o  = '0;
    mem_we_o    = 1'b0;
    mem_wdata_o = '0;
    mem_be_o    = '0;

    unique case (state_q)
      IDLE: begin
        if (job_go_rise) begin
          in_addr_d   = job_in_addr_i;
          out_addr_d  = job_out_addr_i;
          max_len_d   = job_max_len_i;
          n_d         = job_n_i;
          v_d         = 16'd0;
          u_d         = 16'd0;
          bits_left_d = 4'd0;
          fail_d      = 1'b0;
          state_d     = NEW_COEF;
        end
      end

      NEW_COEF: begin
        if (u_q == n_q) begin
          state_d = TRAIL_CHECK;
        end else begin
          phase_d = PH_SIGNMAG;
          sm_acc_d = 8'd0;
          sm_cnt_d = 4'd0;
          state_d  = BIT_NEED;
        end
      end

      // Do we need a fresh byte before the next bit can be consumed?
      BIT_NEED: begin
        if (bits_left_q == 4'd0) begin
          if (v_q >= max_len_q) begin
            fail_d  = 1'b1;
            state_d = FAIL_STATE;
          end else begin
            state_d = FETCH_REQ;
          end
        end else begin
          state_d = CONSUME_BIT;
        end
      end

      FETCH_REQ: begin
        mem_req_o  = 1'b1;
        mem_we_o   = 1'b0;
        mem_addr_o = in_byte_addr;
        mem_be_o   = StrbWidth'(1) << in_byte_addr[2:0];
        if (mem_gnt_i) begin
          state_d = FETCH_WAIT;
        end
      end

      FETCH_WAIT: begin
        if (mem_valid_i) begin
          cur_byte_d  = mem_rdata_i[in_byte_addr[2:0]*8 +: 8];
          bits_left_d = 4'd8;
          v_d         = v_q + 16'd1;
          state_d     = CONSUME_BIT;
        end
      end

      CONSUME_BIT: begin
        logic       bit_val;
        logic [3:0] sm_cnt_next;
        logic [7:0] sm_acc_next;

        bit_val     = cur_byte_q[bits_left_q - 4'd1];
        bits_left_d = bits_left_q - 4'd1;

        if (phase_q == PH_SIGNMAG) begin
          sm_acc_next = {sm_acc_q[6:0], bit_val};
          sm_cnt_next = sm_cnt_q + 4'd1;
          sm_acc_d    = sm_acc_next;
          sm_cnt_d    = sm_cnt_next;
          if (sm_cnt_next == 4'd8) begin
            sign_d  = sm_acc_next[7];
            mag_d   = {5'b0, sm_acc_next[6:0]};
            phase_d = PH_UNARY;
          end
          state_d = BIT_NEED;
        end else begin
          if (bit_val) begin
            // unary terminator found -- coefficient complete
            if (sign_q && mag_q == 12'd0) begin
              fail_d  = 1'b1;
              state_d = FAIL_STATE;
            end else begin
              state_d = WRITE_REQ;
            end
          end else begin
            if (mag_q > 12'd2047 - 12'd128) begin
              // mag_q + 128 would exceed 2047
              fail_d  = 1'b1;
              state_d = FAIL_STATE;
            end else begin
              mag_d   = mag_q + 12'd128;
              state_d = BIT_NEED;
            end
          end
        end
      end

      WRITE_REQ: begin
        mem_req_o   = 1'b1;
        mem_we_o    = 1'b1;
        mem_addr_o  = out_word_addr;
        mem_wdata_o = {4{coeff_val}};
        mem_be_o    = StrbWidth'(4'h3) << out_word_addr[2:0];
        if (mem_gnt_i) begin
          state_d = WRITE_WAIT;
        end
      end

      WRITE_WAIT: begin
        if (mem_valid_i) begin
          u_d     = u_q + 16'd1;
          state_d = NEW_COEF;
        end
      end

      TRAIL_CHECK: begin
        logic [7:0] trail_mask;
        trail_mask = (8'd1 << bits_left_q) - 8'd1;
        if ((cur_byte_q & trail_mask) != 8'd0) begin
          fail_d  = 1'b1;
          state_d = FAIL_STATE;
        end else begin
          state_d = DONE_HOLD;
        end
      end

      FAIL_STATE: begin
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
      phase_q      <= PH_SIGNMAG;
      job_go_old_q <= 1'b0;
      in_addr_q    <= '0;
      out_addr_q   <= '0;
      max_len_q    <= '0;
      n_q          <= '0;
      v_q          <= '0;
      u_q          <= '0;
      cur_byte_q   <= '0;
      bits_left_q  <= '0;
      sm_acc_q     <= '0;
      sm_cnt_q     <= '0;
      sign_q       <= 1'b0;
      mag_q        <= '0;
      fail_q       <= 1'b0;
    end else begin
      state_q      <= state_d;
      phase_q      <= phase_d;
      job_go_old_q <= job_go_i;
      in_addr_q    <= in_addr_d;
      out_addr_q   <= out_addr_d;
      max_len_q    <= max_len_d;
      n_q          <= n_d;
      v_q          <= v_d;
      u_q          <= u_d;
      cur_byte_q   <= cur_byte_d;
      bits_left_q  <= bits_left_d;
      sm_acc_q     <= sm_acc_d;
      sm_cnt_q     <= sm_cnt_d;
      sign_q       <= sign_d;
      mag_q        <= mag_d;
      fail_q       <= fail_d;
    end
  end

endmodule : falcon_decode