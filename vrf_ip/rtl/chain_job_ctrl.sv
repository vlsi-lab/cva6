//
// chain_job_ctrl: SPHINCS+/SLH-DSA SHAKE256 hash-chain job engine for the
// Keccak AXI accelerator, sharing the single keccak_f permutation core with
// the DMA absorb / NTT / rejection-sampler jobs (see vrf_axi_top.sv).
//
// This was originally hashpq_ip's chain_accel.sv SHAKE-chain FSM/datapath,
// ported onto vrf_ip's shared-core job-engine idiom (keccak_dma_ctrl.sv/
// rej_sampler.sv) and re-indexed from chain_accel's 8x32-bit CHAIN/CHAIN2/
// SEED/ADDR register convention onto vrf.hjson's 4x64-bit CHAIN_IO/
// CHAIN_IN2/CHAIN_SEED/CHAIN_ADRS multiregs. Supports the SHAKE256 THASH1
// (F), THASH2 (H) and PRF_ADDR primitives, in both the "simple" and
// "robust" NIST SPHINCS+ constructions. The raw KeccakF1600 permutation
// test mode (chain_accel's raw_kec) is dropped: unused by every caller of
// this job, and vrf_ip's own CSREG/DATA[] raw-permute path is already
// equivalent. hashpq_ip (the original chain_accel/chain_top/chain_axi_top,
// which duplicated the whole Keccak-f[1600] core) has been retired now that
// this module is wired into vrf_axi_top.
//
// Register map (see keccak.hjson):
//   CHAIN_CTRL  [28:27]=op_type [26:19]=step_start [18:11]=steps [10:3]=n
//               [2]=robust [1]=done [0]=go
//   CHAIN_IO[0:3]   (256-bit) -- THASH1/PRF_ADDR input_block1 (input_block1
//               for THASH2 too), AND the output digest register after the
//               job completes
//   CHAIN_SEED[0:3] (256-bit) -- pub_seed
//   CHAIN_ADRS[0:3] (256-bit) -- full 32-byte ADRS
//   CHAIN_IN2[0:3]  (256-bit) -- THASH2 input_block2 (second child)
//
// CHAIN_CTRL.OP_TYPE: 0=PRF_ADDR, 1=THASH1, 2=THASH2, 3=reserved
// CHAIN_CTRL.ROBUST:  0=simple construction, 1=robust construction (bitmask)
//
// Multi-word registers (CHAIN_IO, CHAIN_IN2, CHAIN_SEED, CHAIN_ADRS) use the
// same byte convention throughout: word i holds byte-buffer bytes
// [8i .. 8i+7], with byte 8i at bits [7:0] of word i -- a raw little-endian
// reinterpret-cast of the host byte buffer, matching hal_cva6.h's
// ca_load_*/ca_read_chain helpers' 8-byte-chunk uint64_t copies.
//
// WOTS+ chain stepping: for op_type=THASH1, each pass through the step loop
// (step_cnt = step_start_r .. step_start_r+steps_r-1) overlays the current
// step index into ADRS byte 31 (the "hash address" field, SPX_OFFSET_HASH_ADDR
// per the SPHINCS+ SHAKE reference), which lands at adrs_r[3][63:56] under
// the byte convention above (byte 31 is the top byte of word 3, which spans
// bytes 24-31). Software must therefore leave the low byte of ADRS[3]
// don't-care for THASH1 calls; CHAIN_CTRL.STEP_START doubles as the initial
// ADRS hash-address value.
//
module chain_job_ctrl (
    input  logic        clk_i,
    input  logic        rst_ni,

    // job descriptor, read from the register file (latched at job start)
    input  logic         job_go_i,
    input  logic [1:0]   job_op_type_i,
    input  logic [7:0]   job_n_i,
    input  logic [7:0]   job_steps_i,
    input  logic [7:0]   job_step_start_i,
    input  logic         job_robust_i,

    // job status, latched until software clears CHAIN_CTRL.GO
    output logic         job_done_o,

    // current CHAIN_SEED/CHAIN_ADRS/CHAIN_IN2/CHAIN_IO contents (.q snapshots)
    input  logic [3:0][63:0] seed_rd_i,
    input  logic [3:0][63:0] adrs_rd_i,
    input  logic [3:0][63:0] chain2_rd_i,
    input  logic [3:0][63:0] chain_io_rd_i,

    // CHAIN_IO write-back: this job is CHAIN_IO's only writer, no priority
    // mux needed against any other job type
    output logic [3:0][63:0] chain_io_wr_data_o,
    output logic [3:0]       chain_io_wr_en_o,

    // shared permutation core interface (keccak_f, via vrf_axi_top)
    output logic          perm_start_o,
    input  logic          perm_done_i,
    input  logic [1599:0] perm_dout_i,
    output logic [1599:0] chain_din_o,

    // 1 whenever a chain job is in progress -- qualifies vrf_axi_top's
    // keccak_din mux and (via chain_perm_pending) the DATA[] write-back
    // exclusion, since this job's Keccak I/O is not the resident DATA[]
    // state.
    output logic          chain_active_o
);

    typedef enum logic [3:0] {
        ST_IDLE          = 4'd0,
        ST_SETUP         = 4'd1,
        ST_SHAKE_ABSORB1 = 4'd2,
        ST_SHAKE_WAIT1   = 4'd3,
        ST_SHAKE_ABSORB2 = 4'd4,
        ST_SHAKE_WAIT2   = 4'd5,
        ST_SHAKE_POST    = 4'd6,
        ST_NEXT          = 4'd7,
        ST_DONE_HOLD     = 4'd8
    } state_t;
    state_t state_q, state_d;

    // ── op_type encoding (CHAIN_CTRL.OP_TYPE) ───────────────────────────────
    localparam logic [1:0] OP_PRF_ADDR = 2'b00;
    localparam logic [1:0] OP_THASH1   = 2'b01;
    localparam logic [1:0] OP_THASH2   = 2'b10;

    logic [1:0]  op_type_q, op_type_d;
    logic [7:0]  n_q, n_d;
    logic [7:0]  steps_q, steps_d;
    logic [7:0]  step_start_q, step_start_d;
    logic        robust_q, robust_d;

    // Working registers: latched once at job start from the register file
    // (private state, not the register file itself) -- CHAIN is a
    // self-contained per-call computation, unlike DMA absorb which
    // genuinely operates on persistent DATA[] state.
    logic [3:0][63:0] chain_io_q, chain_io_d;   // input_block1 / output digest
    logic [3:0][63:0] chain2_q, chain2_d;       // input_block2 (THASH2)
    logic [3:0][63:0] seed_q, seed_d;           // pub_seed
    logic [3:0][63:0] adrs_q, adrs_d;           // full 32-byte ADRS

    logic [511:0] bitmask_q, bitmask_d;   // robust-mode bitmask, captured after 1st perm

    logic [7:0] step_cnt_q, step_cnt_d;
    logic [7:0] step_end;
    assign step_end = step_start_q + steps_q;

    logic job_go_old_q;
    logic job_go_rise;
    assign job_go_rise = job_go_i & ~job_go_old_q;

    assign chain_active_o = (state_q != ST_IDLE);

    // ── Byte-serial reversed vectors ────────────────────────────────────────
    // The working registers pack word i = bytes[8i..8i+7] with byte 8i at
    // bits [7:0] (see header comment). To get a flat vector where byte k of
    // the field sits at bits [8k+7:8k] (the convention the ported SHAKE
    // absorption logic below assumes), word 0 must land at the LSB slot and
    // word 3 at the MSB slot of the concatenation.
    logic [255:0] seed_rev;
    logic [255:0] chain_rev;
    logic [255:0] chain2_rev;
    assign seed_rev   = {seed_q[3],   seed_q[2],   seed_q[1],   seed_q[0]};
    assign chain_rev  = {chain_io_q[3], chain_io_q[2], chain_io_q[1], chain_io_q[0]};
    assign chain2_rev = {chain2_q[3],  chain2_q[2],  chain2_q[1],  chain2_q[0]};

    // ADRS word 3 (bytes 24-31) with the WOTS+ chain-step index overlaid into
    // byte 31 (bits [63:56], the SPX_OFFSET_HASH_ADDR byte) for THASH1 only.
    logic [63:0] adrs3_eff;
    assign adrs3_eff = (op_type_q == OP_THASH1) ? {step_cnt_q, adrs_q[3][55:0]}
                                                 : adrs_q[3];

    logic [255:0] addr_rev;
    assign addr_rev = {adrs3_eff, adrs_q[2], adrs_q[1], adrs_q[0]};

    // ── Keccak engine interface ─────────────────────────────────────────────
    logic          kec_start;
    logic [1599:0] kec_state_out;
    logic          kec_done;
    assign perm_start_o = kec_start;
    assign kec_state_out = perm_dout_i;
    assign kec_done      = perm_done_i;

    // SHAKE-chain path: chain_din_o sourced from the absorption state built
    // below, selected per FSM phase (state_1 during ABSORB1/WAIT1,
    // state_2 during ABSORB2/WAIT2 -- held stable across both start+wait
    // cycles so the Keccak engine latches valid data).
    logic [1599:0] shake_state_1;
    logic [1599:0] shake_state_2;
    always_comb begin
        case (state_q)
            ST_SHAKE_ABSORB1, ST_SHAKE_WAIT1: chain_din_o = shake_state_1;
            ST_SHAKE_ABSORB2, ST_SHAKE_WAIT2: chain_din_o = shake_state_2;
            default:                          chain_din_o = '0;
        endcase
    end

    // ── SHAKE256 absorption state construction (per security level) ────────
    // Ported verbatim from chain_accel.sv's rate_1_*/rate_2_* logic.
    // SHAKE256 rate = 136 bytes (1088 bits); capacity = 64 bytes (512 bits).
    // Bit layout: byte 0 at bits [7:0], byte k at bits [8k+7:8k].
    // 0x80 padding always at byte 135 = bits [1087:1080].
    logic [1087:0] rate_1_128, rate_1_192, rate_1_256;
    logic [1087:0] rate_2_128, rate_2_192, rate_2_256;
    logic [1087:0] rate_portion_1, rate_portion_2;

    // ---- State 1: 128-bit security (n_q == 16) ----
    always_comb begin
        rate_1_128 = '0;
        rate_1_128[127:0]   = seed_rev[127:0];
        rate_1_128[383:128] = addr_rev;
        if (robust_q && op_type_q != OP_PRF_ADDR) begin
            // Robust bitmask generation: no payload in state 1.
            rate_1_128[391:384] = 8'h1F;
        end else if (op_type_q == OP_THASH2) begin
            rate_1_128[511:384] = chain_rev[127:0];
            rate_1_128[639:512] = chain2_rev[127:0];
            rate_1_128[647:640] = 8'h1F;
        end else begin
            // PRF_ADDR or simple THASH1: single input block.
            rate_1_128[511:384] = chain_rev[127:0];
            rate_1_128[519:512] = 8'h1F;
        end
        rate_1_128[1087:1080] = 8'h80;
    end

    // ---- State 1: 192-bit security (n_q == 24) ----
    always_comb begin
        rate_1_192 = '0;
        rate_1_192[191:0]   = seed_rev[191:0];
        rate_1_192[447:192] = addr_rev;
        if (robust_q && op_type_q != OP_PRF_ADDR) begin
            rate_1_192[455:448] = 8'h1F;
        end else if (op_type_q == OP_THASH2) begin
            rate_1_192[639:448] = chain_rev[191:0];
            rate_1_192[831:640] = chain2_rev[191:0];
            rate_1_192[839:832] = 8'h1F;
        end else begin
            rate_1_192[639:448] = chain_rev[191:0];
            rate_1_192[647:640] = 8'h1F;
        end
        rate_1_192[1087:1080] = 8'h80;
    end

    // ---- State 1: 256-bit security (n_q == 32) ----
    always_comb begin
        rate_1_256 = '0;
        rate_1_256[255:0]   = seed_rev;
        rate_1_256[511:256] = addr_rev;
        if (robust_q && op_type_q != OP_PRF_ADDR) begin
            rate_1_256[519:512] = 8'h1F;
        end else if (op_type_q == OP_THASH2) begin
            rate_1_256[767:512]   = chain_rev;
            rate_1_256[1023:768]  = chain2_rev;
            rate_1_256[1031:1024] = 8'h1F;
        end else begin
            rate_1_256[767:512] = chain_rev;
            rate_1_256[775:768] = 8'h1F;
        end
        rate_1_256[1087:1080] = 8'h80;
    end

    always_comb begin
        case (n_q)
            8'd16:   rate_portion_1 = rate_1_128;
            8'd24:   rate_portion_1 = rate_1_192;
            8'd32:   rate_portion_1 = rate_1_256;
            default: rate_portion_1 = rate_1_128;
        endcase
    end

    // ---- Robust-mode masked input (state 2 payload) ────────────────────────
    // Pack only the active N-byte portions to avoid pulling zero-padded upper
    // bits from smaller containers into the 2N-byte THASH2 payload.
    logic [511:0] payload_packed;
    always_comb begin
        payload_packed = '0;
        if (op_type_q == OP_THASH2) begin
            case (n_q)
                8'd16:   payload_packed[255:0] = {chain2_rev[127:0], chain_rev[127:0]};
                8'd24:   payload_packed[383:0] = {chain2_rev[191:0], chain_rev[191:0]};
                8'd32:   payload_packed[511:0] = {chain2_rev[255:0], chain_rev[255:0]};
                default: payload_packed[255:0] = {chain2_rev[127:0], chain_rev[127:0]};
            endcase
        end else begin
            case (n_q)
                8'd16:   payload_packed[127:0] = chain_rev[127:0];
                8'd24:   payload_packed[191:0] = chain_rev[191:0];
                8'd32:   payload_packed[255:0] = chain_rev[255:0];
                default: payload_packed[127:0] = chain_rev[127:0];
            endcase
        end
    end

    logic [511:0] masked_input;
    assign masked_input = payload_packed ^ bitmask_q;

    // ---- State 2: robust thash only (pub_seed || addr || masked_input) ----
    always_comb begin
        rate_2_128 = '0;
        rate_2_128[127:0]   = seed_rev[127:0];
        rate_2_128[383:128] = addr_rev;
        if (op_type_q == OP_THASH2) begin
            rate_2_128[639:384] = masked_input[255:0];
            rate_2_128[647:640] = 8'h1F;
        end else begin
            rate_2_128[511:384] = masked_input[127:0];
            rate_2_128[519:512] = 8'h1F;
        end
        rate_2_128[1087:1080] = 8'h80;
    end

    always_comb begin
        rate_2_192 = '0;
        rate_2_192[191:0]   = seed_rev[191:0];
        rate_2_192[447:192] = addr_rev;
        if (op_type_q == OP_THASH2) begin
            rate_2_192[831:448] = masked_input[383:0];
            rate_2_192[839:832] = 8'h1F;
        end else begin
            rate_2_192[639:448] = masked_input[191:0];
            rate_2_192[647:640] = 8'h1F;
        end
        rate_2_192[1087:1080] = 8'h80;
    end

    always_comb begin
        rate_2_256 = '0;
        rate_2_256[255:0]   = seed_rev;
        rate_2_256[511:256] = addr_rev;
        if (op_type_q == OP_THASH2) begin
            rate_2_256[1023:512]  = masked_input[511:0];
            rate_2_256[1031:1024] = 8'h1F;
        end else begin
            rate_2_256[767:512] = masked_input[255:0];
            rate_2_256[775:768] = 8'h1F;
        end
        rate_2_256[1087:1080] = 8'h80;
    end

    always_comb begin
        case (n_q)
            8'd16:   rate_portion_2 = rate_2_128;
            8'd24:   rate_portion_2 = rate_2_192;
            8'd32:   rate_portion_2 = rate_2_256;
            default: rate_portion_2 = rate_2_128;
        endcase
    end

    assign shake_state_1 = {512'b0, rate_portion_1};
    assign shake_state_2 = {512'b0, rate_portion_2};

    // ── FSM ──────────────────────────────────────────────────────────────
    always_comb begin
        state_d       = state_q;
        op_type_d     = op_type_q;
        n_d           = n_q;
        steps_d       = steps_q;
        step_start_d  = step_start_q;
        robust_d      = robust_q;
        chain_io_d    = chain_io_q;
        chain2_d      = chain2_q;
        seed_d        = seed_q;
        adrs_d        = adrs_q;
        bitmask_d     = bitmask_q;
        step_cnt_d    = step_cnt_q;

        kec_start = 1'b0;
        job_done_o = 1'b0;

        chain_io_wr_data_o = chain_io_q;
        chain_io_wr_en_o   = 4'b0000;

        unique case (state_q)
            ST_IDLE: begin
                if (job_go_rise) begin
                    // Latch job descriptor + operands from the register file.
                    op_type_d    = job_op_type_i;
                    n_d          = job_n_i;
                    steps_d      = job_steps_i;
                    step_start_d = job_step_start_i;
                    robust_d     = job_robust_i;
                    chain_io_d   = chain_io_rd_i;
                    chain2_d     = chain2_rd_i;
                    seed_d       = seed_rd_i;
                    adrs_d       = adrs_rd_i;
                    step_cnt_d   = job_step_start_i;
                    state_d      = ST_SETUP;
                end
            end

            ST_SETUP: begin
                if (step_cnt_q == step_end) begin
                    state_d = ST_DONE_HOLD;
                end else begin
                    state_d = ST_SHAKE_ABSORB1;
                end
            end

            // chain_din_o is combinationally driven from shake_state_1
            // (rate_portion_1 for the current n_q/op_type_q/robust_q), so
            // it's already valid when we pulse kec_start here.
            ST_SHAKE_ABSORB1: begin
                kec_start = 1'b1;
                state_d   = ST_SHAKE_WAIT1;
            end

            ST_SHAKE_WAIT1: begin
                if (kec_done) begin
                    if (robust_q && op_type_q != OP_PRF_ADDR) begin
                        // Capture the bitmask (N bytes for THASH1, 2N bytes
                        // for THASH2) from the first permutation's output
                        // before starting the second permutation.
                        case (n_q)
                            8'd16: bitmask_d = (op_type_q == OP_THASH2) ?
                                               {256'd0, kec_state_out[255:0]} :
                                               {384'd0, kec_state_out[127:0]};
                            8'd24: bitmask_d = (op_type_q == OP_THASH2) ?
                                               {128'd0, kec_state_out[383:0]} :
                                               {320'd0, kec_state_out[191:0]};
                            8'd32: bitmask_d = (op_type_q == OP_THASH2) ?
                                               kec_state_out[511:0] :
                                               {256'd0, kec_state_out[255:0]};
                            default: bitmask_d = {384'd0, kec_state_out[127:0]};
                        endcase
                        state_d = ST_SHAKE_ABSORB2;
                    end else begin
                        // PRF_ADDR or simple thash: done after 1 permutation.
                        state_d = ST_SHAKE_POST;
                    end
                end
            end

            ST_SHAKE_ABSORB2: begin
                kec_start = 1'b1;
                state_d   = ST_SHAKE_WAIT2;
            end

            ST_SHAKE_WAIT2: begin
                if (kec_done) state_d = ST_SHAKE_POST;
            end

            // Write back the digest: first bytes of the (last) Keccak
            // permutation output, same byte convention as CHAIN_IO inputs.
            ST_SHAKE_POST: begin
                chain_io_d[0] = kec_state_out[ 63:  0];
                chain_io_d[1] = kec_state_out[127: 64];
                chain_io_d[2] = kec_state_out[191:128];
                chain_io_d[3] = kec_state_out[255:192];

                chain_io_wr_data_o = chain_io_d;
                chain_io_wr_en_o   = 4'b1111;

                state_d = ST_NEXT;
            end

            ST_NEXT: begin
                step_cnt_d = step_cnt_q + 8'd1;
                state_d    = ST_SETUP;
            end

            ST_DONE_HOLD: begin
                job_done_o = 1'b1;
                if (!job_go_i) begin
                    state_d = ST_IDLE;
                end
            end

            default: state_d = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q      <= ST_IDLE;
            job_go_old_q <= 1'b0;
            op_type_q    <= '0;
            n_q          <= '0;
            steps_q      <= '0;
            step_start_q <= '0;
            robust_q     <= 1'b0;
            chain_io_q   <= '0;
            chain2_q     <= '0;
            seed_q       <= '0;
            adrs_q       <= '0;
            bitmask_q    <= '0;
            step_cnt_q   <= '0;
        end else begin
            state_q      <= state_d;
            job_go_old_q <= job_go_i;
            op_type_q    <= op_type_d;
            n_q          <= n_d;
            steps_q      <= steps_d;
            step_start_q <= step_start_d;
            robust_q     <= robust_d;
            chain_io_q   <= chain_io_d;
            chain2_q     <= chain2_d;
            seed_q       <= seed_d;
            adrs_q       <= adrs_d;
            bitmask_q    <= bitmask_d;
            step_cnt_q   <= step_cnt_d;
        end
    end

endmodule : chain_job_ctrl
