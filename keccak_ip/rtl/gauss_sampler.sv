//
// gauss_sampler: hardware offload of HAWK's sig_gauss() CDT-based discrete
// Gaussian sampler (hawk_sign.c, non-AVX2 path), for HAWK-256 (n=256) only.
//
// This module implements ONLY the inner loop of sig_gauss()'s per-lane
// (per-j) squeeze-and-compare work:
//
//   for (block = 0; block < nblocks; block++) {
//       shake_extract(sc, buf, 40);           // <-- this module
//       for (k = 0; k < 4; k++) {             // <-- this module
//           decode lo_k/hi_k from buf;
//           pbit = t[(bitbase+block*16+k) >> 3] >> ((bitbase+...) & 7) & 1;
//           r = CDT-compare(lo_k, hi_k, pbit);
//           x[bitbase + block*16 + k] = sign-and-shift(r);
//           sn += r*r;
//       }
//   }
//
// The outer per-j setup (shake_clone/shake_init, shake_inject(seed,41),
// shake_flip) is left to software, unchanged: this job assumes the
// accelerator's DATA[] state is already hardware-resident for the caller's
// shake_context, with the SHAKE pad10*1 bits already XORed in by
// shake_flip() but NOT yet permuted (dptr == rate, matching every existing
// resident-squeeze call site) -- so the job always starts with one
// unconditional permutation, then squeezes bytes one at a time (mirroring
// keccak_dma_ctrl's byte-at-a-time absorb engine -- simplicity over bus
// efficiency, and it sidesteps all block-boundary realignment logic,
// since 40 does not evenly divide the 136-byte SHAKE256 rate) until 40
// bytes are assembled, at which point 4 samples are produced together
// exactly as sig_gauss() does.
//
// t[]/x[] are read/written one byte at a time over the same simple
// single-outstanding req/gnt/valid memory port keccak_dma_ctrl uses (never
// active at the same time, so the two are muxed onto one external port in
// keccak_axi_top). A t[] byte fetch always needs exactly one byte: bitbase
// is always 4*j (j = 0..3) and block*16 is always a multiple of 16, so the
// 4 needed bits (bitbase + block*16 + {0,1,2,3}) never cross a byte
// boundary -- this module relies on that and does not handle bitbase
// values for which they would.
//
// CDT tables are HAWK-256's sig_gauss_hi_Hawk_256[]/sig_gauss_lo_Hawk_256[]
// (hawk_sign.c), hardcoded (hi_len=8, lo_len=20), same simplicity
// tradeoff as keccak_dma_ctrl hardcoding SHAKE256's 136-byte rate.
//
module gauss_sampler #(
    parameter int unsigned AXI_ADDR_WIDTH = 64,
    parameter int unsigned AXI_DATA_WIDTH = 64
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,

    // job descriptor, read from the register file
    input  logic                        job_go_i,
    input  logic [AXI_ADDR_WIDTH-1:0]   job_t_addr_i,
    input  logic [AXI_ADDR_WIDTH-1:0]   job_x_addr_i,
    input  logic [15:0]                 job_bitbase_i,
    input  logic [15:0]                 job_nblocks_i,

    // job status, latched until software clears SAMP_CTRL.GO
    output logic                        job_done_o,
    output logic [31:0]                 job_sn_o,

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
    input  logic [AXI_DATA_WIDTH-1:0]   mem_rdata_i,

    // 1 whenever a job is in progress (for external mem-port arbitration)
    output logic                        busy_o
);

  // HAWK-256 sig_gauss() CDT tables (hawk_sign.c: sig_gauss_hi_Hawk_256[] /
  // sig_gauss_lo_Hawk_256[]). Values are given exactly as in the C source;
  // all fit within 63 (lo) / 15 (hi) bits, so no masking is needed here --
  // sig_gauss() only ever compares them against already-masked lo/hi.
  localparam int unsigned HiLen = 8;
  localparam int unsigned LoLen = 20;

  localparam logic [15:0] TabHi [0:HiLen-1] = '{
      16'h4D70, 16'h268B, 16'h0F80, 16'h04FA,
      16'h0144, 16'h0041, 16'h000A, 16'h0001
  };
  localparam logic [63:0] TabLo [0:LoLen-1] = '{
      64'h71FBD58485D45050, 64'h1408A4B181C718B1,
      64'h54114F1DC2FA7AC9, 64'h614569CC54722DC9,
      64'h42F74ADDA0B5AE61, 64'h151C5CDCBAFF49A3,
      64'h252E2152AB5D758B, 64'h23460C30AC398322,
      64'h0FDE62196C1718FC, 64'h01355A8330C44097,
      64'h00127325DDF8CEBA, 64'h0000DC8DE401FD12,
      64'h000008100822C548, 64'h0000003B0FFB28F0,
      64'h0000000152A6E9AE, 64'h0000000005EFCD99,
      64'h000000000014DA4A, 64'h0000000000003953,
      64'h000000000000007B, 64'h0000000000000000
  };

  // SHAKE256 rate, same as keccak_dma_ctrl.
  localparam int unsigned RateBytes  = 136;
  localparam logic [7:0]  RateBytesL = 8'(RateBytes);

  typedef enum logic [3:0] {
    IDLE,
    PERM_START,
    PERM_WAIT,
    BYTE_SERVE,
    TREQ,
    TWAIT,
    COMPUTE,
    XREQ,
    XWAIT,
    DONE_HOLD
  } state_e;

  state_e state_q, state_d;

  logic                      job_go_old_q;
  logic [AXI_ADDR_WIDTH-1:0] t_addr_q, t_addr_d;
  logic [AXI_ADDR_WIDTH-1:0] x_addr_q, x_addr_d;
  logic [15:0]               bitbase_q, bitbase_d;
  logic [15:0]               nblocks_q, nblocks_d;
  logic [15:0]               block_idx_q, block_idx_d;
  logic [31:0]               sn_q, sn_d;

  logic [7:0]                blk_off_q, blk_off_d;   // position within the current rate block
  logic [5:0]                byte_idx_q, byte_idx_d; // 0..39, position within the 40-byte assembly buffer
  logic [7:0]                blk_off_next;           // blk_off_q+1, precomputed for BYTE_SERVE
  logic [5:0]                byte_idx_next;          // byte_idx_q+1, precomputed for BYTE_SERVE
  logic                      perm_initial_q, perm_initial_d;
  logic [319:0]              buf40_q, buf40_d;        // assembled 40-byte squeeze chunk

  logic [7:0]                t_byte_q;
  logic [1:0]                xk_q, xk_d;              // which of the 4 output bytes (0..3)
  logic signed [7:0]         xbyte0_q, xbyte1_q, xbyte2_q, xbyte3_q;

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

  assign blk_off_next  = blk_off_q + 8'd1;
  assign byte_idx_next = byte_idx_q + 6'd1;

  // t[] byte address for this block: bitbase and block*16 are always
  // multiples of 4, so (bitbase + block*16) mod 8 is always 0 or 4 --
  // the 4 needed bits never cross the fetched byte.
  logic [AXI_ADDR_WIDTH-1:0] t_bit_index;
  logic [AXI_ADDR_WIDTH-1:0] t_byte_addr;
  logic [2:0]                t_bit_off;
  assign t_bit_index = AXI_ADDR_WIDTH'(bitbase_q) + (AXI_ADDR_WIDTH'(block_idx_q) << 4);
  assign t_byte_addr = t_addr_q + (t_bit_index >> 3);
  assign t_bit_off   = t_bit_index[2:0];

  // decode the 4 lo/hi/neg samples from the assembled 40-byte buffer
  // (byte 0 = buf40_q[7:0], matching sig_gauss()'s little-endian dec64le/
  // dec16le reads).
  logic [63:0] lo0, lo1, lo2, lo3;
  logic        neg0, neg1, neg2, neg3;
  logic [15:0] hi0, hi1, hi2, hi3;
  assign lo0 = buf40_q[  0 +: 64] & 64'h7FFFFFFFFFFFFFFF;
  assign lo1 = buf40_q[ 64 +: 64] & 64'h7FFFFFFFFFFFFFFF;
  assign lo2 = buf40_q[128 +: 64] & 64'h7FFFFFFFFFFFFFFF;
  assign lo3 = buf40_q[192 +: 64] & 64'h7FFFFFFFFFFFFFFF;
  assign neg0 = buf40_q[ 63];
  assign neg1 = buf40_q[127];
  assign neg2 = buf40_q[191];
  assign neg3 = buf40_q[255];
  assign hi0 = buf40_q[256 +: 16] & 16'h7FFF;
  assign hi1 = buf40_q[272 +: 16] & 16'h7FFF;
  assign hi2 = buf40_q[288 +: 16] & 16'h7FFF;
  assign hi3 = buf40_q[304 +: 16] & 16'h7FFF;

  // t_bit_off is always 0 or 4 (see t_bit_index derivation above), so
  // t_bit_off+3 is always <= 7 and never crosses out of t_byte_q -- widen
  // to 4 bits purely so the addition is never mistaken for a mod-8 wrap.
  logic pbit0, pbit1, pbit2, pbit3;
  assign pbit0 = t_byte_q[{1'b0, t_bit_off} + 4'd0];
  assign pbit1 = t_byte_q[{1'b0, t_bit_off} + 4'd1];
  assign pbit2 = t_byte_q[{1'b0, t_bit_off} + 4'd2];
  assign pbit3 = t_byte_q[{1'b0, t_bit_off} + 4'd3];

  // r = number of CDT thresholds this sample's (lo,hi) draw exceeds --
  // directly mirrors sig_gauss()'s two comparison loops (hi_len entries
  // compared on both hi and lo, remaining lo_len-hi_len entries compared
  // on lo only, gated by hinz = (hi == 0)).
  function automatic logic [3:0] gauss_r(
      input logic [63:0] lo,
      input logic [15:0] hi,
      input logic        pbit
  );
    logic [3:0] r;
    logic       hinz;
    logic [63:0] tlo;
    logic [15:0] thi;
    logic        cc;
    r = 4'd0;
    for (int p = 0; p < HiLen/2; p++) begin
      tlo = pbit ? TabLo[2*p+1] : TabLo[2*p];
      thi = pbit ? TabHi[2*p+1] : TabHi[2*p];
      cc  = (lo < tlo);
      if ((hi < thi) || (hi == thi && cc)) begin
        r = r + 4'd1;
      end
    end
    hinz = (hi == 16'd0);
    for (int p = HiLen/2; p < LoLen/2; p++) begin
      tlo = pbit ? TabLo[2*p+1] : TabLo[2*p];
      cc  = (lo < tlo);
      if (hinz && cc) begin
        r = r + 4'd1;
      end
    end
    return r;
  endfunction

  // magnitude before sign: sig_gauss() computes
  // "r = (r << 1) - p_oddw" where p_oddw is pbit sign-extended to 32 bits
  // (i.e. p_oddw = pbit ? 0xFFFFFFFF : 0, NOT pbit itself) -- subtracting
  // that two's-complement -1 is the same as ADDING 1, so the actual
  // magnitude is rmag = (r << 1) + pbit, always >= 0 (r in 0..10, pbit in
  // 0..1 -> rmag in 0..21).
  function automatic logic signed [7:0] gauss_rmag(
      input logic [3:0] r,
      input logic       pbit
  );
    logic signed [7:0] r_ext;
    r_ext = $signed({4'b0, r});
    return (r_ext <<< 1) + $signed({7'b0, pbit});
  endfunction

  logic [3:0] r0, r1, r2, r3;
  logic signed [7:0] rmag0, rmag1, rmag2, rmag3;
  logic signed [7:0] xbyte0, xbyte1, xbyte2, xbyte3;
  logic [15:0] sq0, sq1, sq2, sq3;

  assign r0 = gauss_r(lo0, hi0, pbit0);
  assign r1 = gauss_r(lo1, hi1, pbit1);
  assign r2 = gauss_r(lo2, hi2, pbit2);
  assign r3 = gauss_r(lo3, hi3, pbit3);

  assign rmag0 = gauss_rmag(r0, pbit0);
  assign rmag1 = gauss_rmag(r1, pbit1);
  assign rmag2 = gauss_rmag(r2, pbit2);
  assign rmag3 = gauss_rmag(r3, pbit3);

  assign xbyte0 = neg0 ? -rmag0 : rmag0;
  assign xbyte1 = neg1 ? -rmag1 : rmag1;
  assign xbyte2 = neg2 ? -rmag2 : rmag2;
  assign xbyte3 = neg3 ? -rmag3 : rmag3;

  assign sq0 = 16'(rmag0 * rmag0);
  assign sq1 = 16'(rmag1 * rmag1);
  assign sq2 = 16'(rmag2 * rmag2);
  assign sq3 = 16'(rmag3 * rmag3);

  localparam int unsigned StrbWidth = AXI_DATA_WIDTH / 8;

  logic [AXI_ADDR_WIDTH-1:0] x_byte_addr;
  logic [2:0]                x_byte_lane;
  assign x_byte_addr = x_addr_q + (AXI_ADDR_WIDTH'(block_idx_q) << 4)
                        + AXI_ADDR_WIDTH'({30'b0, xk_q});
  assign x_byte_lane = x_byte_addr[2:0];

  logic signed [7:0] xk_byte;
  always_comb begin
    unique case (xk_q)
      2'd0: xk_byte = xbyte0_q;
      2'd1: xk_byte = xbyte1_q;
      2'd2: xk_byte = xbyte2_q;
      default: xk_byte = xbyte3_q;
    endcase
  end

  always_comb begin
    state_d      = state_q;
    t_addr_d     = t_addr_q;
    x_addr_d     = x_addr_q;
    bitbase_d    = bitbase_q;
    nblocks_d    = nblocks_q;
    block_idx_d  = block_idx_q;
    sn_d         = sn_q;
    blk_off_d    = blk_off_q;
    byte_idx_d   = byte_idx_q;
    perm_initial_d = perm_initial_q;
    buf40_d      = buf40_q;
    xk_d         = xk_q;

    perm_start_o = 1'b0;
    job_done_o   = 1'b0;

    mem_req_o   = 1'b0;
    mem_addr_o  = t_byte_addr;
    mem_we_o    = 1'b0;
    mem_wdata_o = '0;
    mem_be_o    = '0;

    unique case (state_q)
      IDLE: begin
        if (job_go_rise) begin
          t_addr_d       = job_t_addr_i;
          x_addr_d       = job_x_addr_i;
          bitbase_d      = job_bitbase_i;
          nblocks_d      = job_nblocks_i;
          block_idx_d    = 16'd0;
          sn_d           = 32'd0;
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
            byte_idx_d     = 6'd0;
            perm_initial_d = 1'b0;
            state_d        = BYTE_SERVE;
          end else if (byte_idx_q == 6'd40) begin
            // this permutation was triggered by a rate-block wrap that
            // coincided exactly with the 40th (last) byte this chunk
            // needed (e.g. byte 680 = 5*136 = 17*40) -- all 40 bytes are
            // already assembled, so go straight to the t-byte fetch
            // instead of serving (nonexistent) further bytes.
            state_d = TREQ;
          end else begin
            state_d = BYTE_SERVE;
          end
        end
      end

      BYTE_SERVE: begin
        buf40_d[byte_idx_q*8 +: 8] = cur_squeeze_byte;
        byte_idx_d = byte_idx_next;
        if (blk_off_next == RateBytesL) begin
          blk_off_d      = 8'd0;
          perm_initial_d = 1'b0;
          state_d        = PERM_START;
        end else begin
          blk_off_d = blk_off_next;
          state_d   = (byte_idx_q == 6'd39) ? TREQ : BYTE_SERVE;
        end
      end

      TREQ: begin
        mem_req_o  = 1'b1;
        mem_addr_o = t_byte_addr;
        mem_we_o   = 1'b0;
        if (mem_gnt_i) begin
          state_d = TWAIT;
        end
      end

      TWAIT: begin
        if (mem_valid_i) begin
          state_d = COMPUTE;
        end
      end

      COMPUTE: begin
        sn_d   = sn_q + 32'(sq0) + 32'(sq1) + 32'(sq2) + 32'(sq3);
        xk_d   = 2'd0;
        state_d = XREQ;
      end

      XREQ: begin
        mem_req_o   = 1'b1;
        mem_addr_o  = x_byte_addr;
        mem_we_o    = 1'b1;
        mem_wdata_o = {8{xk_byte}};
        mem_be_o    = StrbWidth'(1) << x_byte_lane;
        if (mem_gnt_i) begin
          state_d = XWAIT;
        end
      end

      XWAIT: begin
        if (mem_valid_i) begin
          if (xk_q == 2'd3) begin
            if (block_idx_q + 16'd1 == nblocks_q) begin
              state_d = DONE_HOLD;
            end else begin
              block_idx_d = block_idx_q + 16'd1;
              byte_idx_d  = 6'd0;
              state_d     = BYTE_SERVE;
            end
          end else begin
            xk_d    = xk_q + 2'd1;
            state_d = XREQ;
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

  // latch the 4 computed output bytes once, right when leaving COMPUTE,
  // so XREQ/XWAIT can stream them out one at a time without recomputing.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      xbyte0_q <= '0;
      xbyte1_q <= '0;
      xbyte2_q <= '0;
      xbyte3_q <= '0;
    end else if (state_q == COMPUTE) begin
      xbyte0_q <= xbyte0;
      xbyte1_q <= xbyte1;
      xbyte2_q <= xbyte2;
      xbyte3_q <= xbyte3;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= IDLE;
      job_go_old_q   <= 1'b0;
      t_addr_q       <= '0;
      x_addr_q       <= '0;
      bitbase_q      <= '0;
      nblocks_q      <= '0;
      block_idx_q    <= '0;
      sn_q           <= '0;
      blk_off_q      <= '0;
      byte_idx_q     <= '0;
      perm_initial_q <= 1'b0;
      buf40_q        <= '0;
      xk_q           <= '0;
      t_byte_q       <= '0;
    end else begin
      state_q        <= state_d;
      job_go_old_q   <= job_go_i;
      t_addr_q       <= t_addr_d;
      x_addr_q       <= x_addr_d;
      bitbase_q      <= bitbase_d;
      nblocks_q      <= nblocks_d;
      block_idx_q    <= block_idx_d;
      sn_q           <= sn_d;
      blk_off_q      <= blk_off_d;
      byte_idx_q     <= byte_idx_d;
      perm_initial_q <= perm_initial_d;
      buf40_q        <= buf40_d;
      xk_q           <= xk_d;
      if (state_q == TWAIT && mem_valid_i) begin
        t_byte_q <= mem_rdata_i[t_byte_addr[2:0]*8 +: 8];
      end
    end
  end

  assign job_sn_o = sn_q;

endmodule : gauss_sampler
