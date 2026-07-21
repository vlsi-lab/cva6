//
// keccak_dma_ctrl: DMA job engine for the Keccak AXI accelerator.
//
// Phase 1: absorbs JOB_SRC_LEN raw bytes from JOB_SRC_ADDR directly out of
// CVA6 memory, XOR-absorbing them one byte at a time into the resident
// 1600-bit state (the same DATA[] registers the legacy CSREG/raw-permute
// path uses), triggering the shared keccak_f permutation itself whenever a
// full SHAKE256 rate block (136 bytes / 17 words) has been absorbed --
// chaining as many blocks as the job requires with no CPU round trip in
// between. Optionally zeroes the state first (FRESH, i.e. this is the
// first block of a brand new sponge context) and/or applies the SHAKE
// pad10*1 padding after the absorb (FLIP, mirroring shake_flip()) without
// forcing an extra permutation, matching the software sponge exactly.
//
// Absorption is byte-at-a-time by design, not word-at-a-time: JOB_SRC_ADDR
// and JOB_DPTR (the starting offset within the current rate block) are
// each independently arbitrary byte alignments in real HAWK call sites
// (e.g. a single-byte counter variable), and a byte-wise engine sidesteps
// all cross-word realignment logic entirely -- simplicity over maximum
// bus efficiency, so the sponge math stays trivially easy to verify
// against the NIST reference bit-for-bit.
//
// The bus-facing port is the same plain single-outstanding
// request/grant/valid interface used in Phase 0 (see that revision's
// header for the rationale); axi_adapter wraps it into real AXI4 one level
// up, in keccak_axi_top.
//

module keccak_dma_ctrl #(
    parameter int unsigned AXI_ADDR_WIDTH = 64,
    parameter int unsigned AXI_DATA_WIDTH = 64
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,

    // job descriptor, read from the register file
    input  logic                        job_go_i,
    input  logic [AXI_ADDR_WIDTH-1:0]   job_src_addr_i,
    input  logic [31:0]                 job_src_len_i,
    input  logic                        job_fresh_i,
    input  logic                        job_flip_i,
    input  logic [7:0]                  job_dptr_i,

    // job status, latched until software clears JOBCTRL.GO
    output logic                        job_done_o,

    // DATA[] register write-back: single-word XOR-absorb write, and a
    // one-cycle bulk-zero pulse (arbitrated with the permutation-output
    // write path in keccak_axi_top)
    output logic [4:0]                  word_wr_idx_o,
    output logic [AXI_DATA_WIDTH-1:0]   word_wr_data_o,
    output logic                        word_wr_en_o,
    output logic                        zero_all_o,

    // current DATA[] contents, read back for the XOR read-modify-write
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
    input  logic [AXI_DATA_WIDTH-1:0]   mem_rdata_i
);

  // SHAKE256 rate: 136 bytes = 17 words -- HAWK's only usage, hardcoded to
  // keep the absorb engine simple (see keccak_ip design notes).
  localparam int unsigned RateBytes   = 136;
  localparam logic [7:0]  RateBytesL  = 8'(RateBytes);
  localparam logic [4:0]  LastWordIdx = 5'((RateBytes - 1) >> 3);
  localparam logic [2:0]  LastByteLane = 3'((RateBytes - 1) & 7);

  typedef enum logic [3:0] {
    IDLE,
    ZERO_INIT,
    BYTE_REQ,
    BYTE_WAIT,
    PERM_START,
    PERM_WAIT,
    FLIP_BYTE0,
    FLIP_BYTE1,
    DONE_HOLD
  } state_e;

  state_e state_q, state_d;

  logic                      job_go_old_q;
  logic [AXI_ADDR_WIDTH-1:0] src_addr_q, src_addr_d;
  logic [31:0]               src_len_q, src_len_d;
  logic [31:0]               byte_cnt_q, byte_cnt_d;
  logic [7:0]                blk_off_q, blk_off_d;
  logic                      flip_q, flip_d;

  logic job_go_rise;
  assign job_go_rise = job_go_i & ~job_go_old_q;

  // helper: XOR one byte into a word at the given byte lane
  function automatic logic [AXI_DATA_WIDTH-1:0] xor_byte(
      input logic [AXI_DATA_WIDTH-1:0] cur_word,
      input logic [2:0]                byte_lane,
      input logic [7:0]                new_byte
  );
    logic [AXI_DATA_WIDTH-1:0] result;
    result = cur_word;
    result[byte_lane*8+:8] = cur_word[byte_lane*8+:8] ^ new_byte;
    return result;
  endfunction

  // position of the byte currently being absorbed within the rate block
  logic [4:0] cur_word_idx;
  logic [2:0] cur_byte_lane;
  assign cur_word_idx  = blk_off_q[7:3];
  assign cur_byte_lane = blk_off_q[2:0];

  // address/lane of the next source byte to fetch
  logic [AXI_ADDR_WIDTH-1:0] byte_addr;
  logic [2:0]                byte_addr_lane;
  assign byte_addr      = src_addr_q + AXI_ADDR_WIDTH'(byte_cnt_q);
  assign byte_addr_lane = byte_addr[2:0];

  logic [7:0] fetched_byte;
  assign fetched_byte = mem_rdata_i[byte_addr_lane*8+:8];

  localparam int unsigned StrbWidth = AXI_DATA_WIDTH / 8;

  always_comb begin
    state_d    = state_q;
    src_addr_d = src_addr_q;
    src_len_d  = src_len_q;
    byte_cnt_d = byte_cnt_q;
    blk_off_d  = blk_off_q;
    flip_d     = flip_q;

    mem_req_o   = 1'b0;
    mem_addr_o  = byte_addr;
    mem_we_o    = 1'b0;
    mem_wdata_o = '0;
    mem_be_o    = StrbWidth'(1) << byte_addr_lane;

    word_wr_idx_o  = cur_word_idx;
    word_wr_data_o = '0;
    word_wr_en_o   = 1'b0;
    zero_all_o     = 1'b0;

    perm_start_o = 1'b0;
    job_done_o   = 1'b0;

    unique case (state_q)
      IDLE: begin
        if (job_go_rise) begin
          src_addr_d = job_src_addr_i;
          src_len_d  = job_src_len_i;
          byte_cnt_d = 32'd0;
          blk_off_d  = job_dptr_i;
          flip_d     = job_flip_i;
          state_d    = job_fresh_i ? ZERO_INIT : BYTE_REQ;
        end
      end

      // single-cycle bulk zero of all 25 DATA words (shake_init's memset)
      ZERO_INIT: begin
        zero_all_o = 1'b1;
        state_d    = BYTE_REQ;
      end

      BYTE_REQ: begin
        if (byte_cnt_q == src_len_q) begin
          state_d = flip_q ? FLIP_BYTE0 : DONE_HOLD;
        end else begin
          mem_req_o = 1'b1;
          if (mem_gnt_i) begin
            state_d = BYTE_WAIT;
          end
        end
      end

      BYTE_WAIT: begin
        if (mem_valid_i) begin
          word_wr_idx_o  = cur_word_idx;
          word_wr_data_o = xor_byte(word_rd_data_i[cur_word_idx], cur_byte_lane, fetched_byte);
          word_wr_en_o   = 1'b1;

          byte_cnt_d = byte_cnt_q + 32'd1;
          blk_off_d  = blk_off_q + 8'd1;

          state_d = (blk_off_d == RateBytesL) ? PERM_START : BYTE_REQ;
        end
      end

      PERM_START: begin
        perm_start_o = 1'b1;
        state_d      = PERM_WAIT;
      end

      PERM_WAIT: begin
        if (perm_done_i) begin
          blk_off_d = 8'd0;
          state_d   = (byte_cnt_q == src_len_q) ? (flip_q ? FLIP_BYTE0 : DONE_HOLD) : BYTE_REQ;
        end
      end

      // pad10*1: XOR 0x1F at the current fill position, 0x80 at the last
      // rate byte -- exactly shake_flip()'s two XORs, never forcing a
      // permutation (matches the software sponge: flip only sets bits,
      // the next squeeze triggers the actual permute)
      FLIP_BYTE0: begin
        word_wr_idx_o  = cur_word_idx;
        word_wr_data_o = xor_byte(word_rd_data_i[cur_word_idx], cur_byte_lane, 8'h1F);
        word_wr_en_o   = 1'b1;
        state_d        = FLIP_BYTE1;
      end

      FLIP_BYTE1: begin
        word_wr_idx_o  = LastWordIdx;
        word_wr_data_o = xor_byte(word_rd_data_i[LastWordIdx], LastByteLane, 8'h80);
        word_wr_en_o   = 1'b1;
        state_d        = DONE_HOLD;
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
      src_addr_q   <= '0;
      src_len_q    <= '0;
      byte_cnt_q   <= '0;
      blk_off_q    <= '0;
      flip_q       <= 1'b0;
    end else begin
      state_q      <= state_d;
      job_go_old_q <= job_go_i;
      src_addr_q   <= src_addr_d;
      src_len_q    <= src_len_d;
      byte_cnt_q   <= byte_cnt_d;
      blk_off_q    <= blk_off_d;
      flip_q       <= flip_d;
    end
  end

endmodule : keccak_dma_ctrl
