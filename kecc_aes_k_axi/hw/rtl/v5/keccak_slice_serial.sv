// Slice-serial Keccak-f[1600]: processes PARALLEL_SLICES bits of all 25
// lanes per cycle instead of computing a full 1600-bit round
// combinationally (rtl/keccak_round.sv's approach). Independently derived
// and validated against a Python model (itself cross-checked against the
// real, RTL-validated keccak_round.sv) before being written here -- see
// implementation.md's v5 entry for the derivation and the tradeoff
// against keccak_round.sv (much less area, ~(KECCAK_ROUNDS+1) *
// (64/PARALLEL_SLICES) + a few cycles per permutation instead of 24).
// Not a port of any reference implementation -- see implementation.md.
//
// Round-function reordering: chi+iota computed first (from a rho-rotated
// read of the previous round's post-theta state), theta computed last
// (on that same cycle's chi+iota output, no extra memory read needed).
// rho is never computed as a rotate; it's folded into which (slice, bit)
// gets read. One extra "priming" group (group 0) applies theta only to
// the raw input state (no chi/iota) to bootstrap B_0 = rho(theta(state_in));
// the final group (group KECCAK_ROUNDS) applies chi+iota only (no
// trailing theta), producing the actual permutation result directly.
//
// theta's D[x] needs a "carry" (the previous slice's column-parity top
// bit) that, for slice 0 of every group, isn't known until slice
// NUM_SUB_ROUNDS-1 of the *same* group has been processed. Resolved with
// a placeholder-then-patch scheme: slice 0 is written using carry=0, and
// once the true carry is known (one cycle after the last slice), a
// dedicated patch cycle XORs bit 0 of slice 0 for the affected lanes.

`default_nettype none

import pkg_keccak::k_state;

module keccak_slice_serial #(
    parameter int unsigned PARALLEL_SLICES = 4
) (
    input  wire             clk,
    input  wire             reset_n,
    input  wire             start,        // pulse: begin permutation of state_in
    input  wire [1599 : 0]  state_in,
    output wire             done,         // 1-cycle pulse, state_out valid that cycle
    output wire [1599 : 0]  state_out
);

  localparam int unsigned P              = PARALLEL_SLICES;
  localparam int unsigned NUM_SUB_ROUNDS = 64 / P;
  localparam int unsigned ADDR_W         = $clog2(NUM_SUB_ROUNDS);
  localparam int unsigned KECCAK_ROUNDS  = 24;

  //----------------------------------------------------------------
  // Elaboration-time lane tables: rho's offset (existing 25-entry table,
  // same values as rho_out's always_comb block in keccak_round.sv), split
  // into an address offset (whole slices) and a bit offset (within one
  // slice) -- and pi's inverse mapping (which source lane a given
  // (Y,X) output position reads from post-pi).
  //----------------------------------------------------------------
  function automatic int unsigned rho_offset(input int unsigned y, input int unsigned x);
    // NOTE: was `case ({y,x})` against 6-bit case items -- {y,x} concats
    // two 32-bit `int`s (64 bits), which silently never matched any item
    // and always fell through to the default (ADDR_OFF=0 for every
    // lane), breaking rho for every non-zero offset. y*5+x avoids any
    // concatenation-width mismatch (plain int, plain int literals).
    case (y*5 + x)
      0: rho_offset = 0;    1: rho_offset = 1;    2: rho_offset = 62;
      3: rho_offset = 28;   4: rho_offset = 27;
      5: rho_offset = 36;   6: rho_offset = 44;   7: rho_offset = 6;
      8: rho_offset = 55;   9: rho_offset = 20;
      10: rho_offset = 3;   11: rho_offset = 10;  12: rho_offset = 43;
      13: rho_offset = 25;  14: rho_offset = 39;
      15: rho_offset = 41;  16: rho_offset = 45;  17: rho_offset = 15;
      18: rho_offset = 21;  19: rho_offset = 8;
      20: rho_offset = 18;  21: rho_offset = 2;   22: rho_offset = 61;
      23: rho_offset = 56;  24: rho_offset = 14;
      default:     rho_offset = 0;
    endcase
  endfunction

  function automatic int unsigned pi_inv_x(input int unsigned A, input int unsigned Bp);
    // pi_out[A][Bp] = pi_in[y'][x'] where y'=Bp and (2x'+3y')%5==A.
    int unsigned x;
    pi_inv_x = 0;
    for (x = 0; x < 5; x = x + 1)
      if ((2*x + 3*Bp) % 5 == A)
        pi_inv_x = x;
  endfunction

  //----------------------------------------------------------------
  // FSM: group_idx (0..KECCAK_ROUNDS), slice_idx (0..NUM_SUB_ROUNDS-1),
  // a one-cycle PATCH phase after each group that has a theta step.
  //----------------------------------------------------------------
  typedef enum logic [1:0] {ST_IDLE, ST_SWEEP, ST_PATCH} state_t;
  state_t st_reg, st_new;

  logic [4:0]         group_idx_reg, group_idx_new;
  logic [ADDR_W-1:0]  slice_idx_reg, slice_idx_new;
  logic [4:0]         carry_reg, carry_new;   // one bit per column x

  wire is_priming   = (group_idx_reg == 5'd0);
  wire is_final      = (group_idx_reg == 5'(KECCAK_ROUNDS));
  wire needs_theta    = !is_final;
  wire needs_chi_iota  = !is_priming;
  wire last_slice     = (slice_idx_reg == ADDR_W'(NUM_SUB_ROUNDS-1));

  wire buf_sel_write = group_idx_reg[0];
  wire buf_sel_read  = !group_idx_reg[0];

  //----------------------------------------------------------------
  // Round constant for this group (groups 1..KECCAK_ROUNDS use
  // RC8[group_idx-1]) -- reuse the existing, already-verified generator.
  //----------------------------------------------------------------
  wire [7:0] rc8;
  keccak_round_constants_gen u_rc (
      .round_number            (group_idx_reg - 5'd1),
      .round_constant_signal_out (rc8)
  );

  //----------------------------------------------------------------
  // Storage: 2 buffers x 25 lanes, each a small distributed RAM
  // (NUM_SUB_ROUNDS deep, P bits wide, 2 async read ports + 1 sync write).
  //----------------------------------------------------------------
  logic [P-1:0] rd0 [0:1][0:4][0:4];
  logic [P-1:0] rd1 [0:1][0:4][0:4];
  logic [P-1:0] wr_data [0:1][0:4][0:4];
  logic         wr_en   [0:1];
  logic [ADDR_W-1:0] wr_addr [0:1];
  logic [ADDR_W-1:0] raddr0 [0:4][0:4];
  logic [ADDR_W-1:0] raddr1 [0:4][0:4];

  genvar gy, gx, gb;
  generate
    for (gb = 0; gb < 2; gb = gb + 1) begin : gen_buf
      for (gy = 0; gy < 5; gy = gy + 1) begin : gen_y
        for (gx = 0; gx < 5; gx = gx + 1) begin : gen_x
          keccak_lane_mem #(.WIDTH(P), .DEPTH(NUM_SUB_ROUNDS), .ADDR_W(ADDR_W)) u_mem (
              .clk    (clk),
              .we     (wr_en[gb]),
              .waddr  (wr_addr[gb]),
              .wdata  (wr_data[gb][gy][gx]),
              .raddr0 (raddr0[gy][gx]),
              .rdata0 (rd0[gb][gy][gx]),
              .raddr1 (raddr1[gy][gx]),
              .rdata1 (rd1[gb][gy][gx])
          );
        end
      end
    end
  endgenerate

  //----------------------------------------------------------------
  // Read addressing: raddr0/raddr1 shared across both buffers (only the
  // selected buffer's data is used, per lane, via buf_sel_read) --
  // src_s = (slice_idx - addr_off) mod NUM_SUB_ROUNDS, src_s_prev = src_s-1.
  //----------------------------------------------------------------
  generate
    for (gy = 0; gy < 5; gy = gy + 1) begin : gen_raddr_y
      for (gx = 0; gx < 5; gx = gx + 1) begin : gen_raddr_x
        localparam int unsigned OFF      = rho_offset(gy, gx);
        localparam int unsigned ADDR_OFF = OFF / P;
        // raddr0/raddr1 computed combinationally from slice_idx_reg each
        // cycle -- ADDR_OFF is a per-lane elaboration-time constant, the
        // subtraction+modulo is the only runtime part (small, ADDR_W bits).
        assign raddr0[gy][gx] = ADDR_W'((32'(slice_idx_reg) + NUM_SUB_ROUNDS*2 - ADDR_OFF) % NUM_SUB_ROUNDS);
        assign raddr1[gy][gx] = ADDR_W'((32'(slice_idx_reg) + NUM_SUB_ROUNDS*2 - ADDR_OFF - 1) % NUM_SUB_ROUNDS);
      end
    end
  endgenerate

  //----------------------------------------------------------------
  // rot[y][x]: rho-rotated read for this slice (groups 1..KECCAK_ROUNDS
  // only -- group 0 uses raw_in instead, see below). bit_off is a
  // per-lane elaboration-time constant: when it's 0, this is a plain
  // wire (no logic), matching rho's real hardware cost of zero.
  //----------------------------------------------------------------
  logic [P-1:0] rot     [0:4][0:4];
  logic [P-1:0] raw_in  [0:4][0:4];

  generate
    for (gy = 0; gy < 5; gy = gy + 1) begin : gen_rot_y
      for (gx = 0; gx < 5; gx = gx + 1) begin : gen_rot_x
        localparam int unsigned OFF     = rho_offset(gy, gx);
        localparam int unsigned BIT_OFF = OFF % P;
        wire [P-1:0] val      = buf_sel_read ? rd0[1][gy][gx] : rd0[0][gy][gx];
        wire [P-1:0] val_prev = buf_sel_read ? rd1[1][gy][gx] : rd1[0][gy][gx];
        if (BIT_OFF == 0) begin : gen_no_shift
          assign rot[gy][gx] = val;
        end else begin : gen_shift
          assign rot[gy][gx] = P'(val_prev[P-1 -: BIT_OFF]) | (P'(val[P-BIT_OFF-1:0]) << BIT_OFF);
        end
        // group 0 (priming) reads state_in directly, canonical (no
        // rotation -- theta itself doesn't rotate), slice_idx_reg-th
        // P-bit chunk of this lane's 64 bits.
        assign raw_in[gy][gx] = state_in[64*(5*gy+gx) + P*slice_idx_reg +: P];
      end
    end
  endgenerate

  //----------------------------------------------------------------
  // pi: pure rewiring (piv[Y][X] = rot_or_raw[pi_inv_y][pi_inv_x]) --
  // elaboration-time constant indices, zero logic cost, same as the
  // full-round keccak_round.sv's pi stage.
  //----------------------------------------------------------------
  logic [P-1:0] src_val [0:4][0:4];   // rot for groups >=1, raw_in for group 0
  logic [P-1:0] piv     [0:4][0:4];

  generate
    for (gy = 0; gy < 5; gy = gy + 1) begin : gen_src_y
      for (gx = 0; gx < 5; gx = gx + 1) begin : gen_src_x
        assign src_val[gy][gx] = needs_chi_iota ? rot[gy][gx] : raw_in[gy][gx];
      end
    end
    for (gy = 0; gy < 5; gy = gy + 1) begin : gen_pi_y
      for (gx = 0; gx < 5; gx = gx + 1) begin : gen_pi_x
        localparam int unsigned SRC_Y = gx;
        localparam int unsigned SRC_X = pi_inv_x(gy, gx);
        assign piv[gy][gx] = src_val[SRC_Y][SRC_X];
      end
    end
  endgenerate

  //----------------------------------------------------------------
  // chi + iota: a_slice[y][x] = piv[y][x] ^ (~piv[y][x+1] & piv[y][x+2]),
  // only when needs_chi_iota (group 0's priming pass bypasses this,
  // a_slice = src_val directly, matching keccak_round.sv's iota bit
  // positions {0,1,2,3,7,15,31,63} of lane (0,0), whichever ones fall
  // within the current P-bit slice).
  //----------------------------------------------------------------
  logic [P-1:0] a_slice [0:4][0:4];

  generate
    for (gy = 0; gy < 5; gy = gy + 1) begin : gen_chi_y
      for (gx = 0; gx < 5; gx = gx + 1) begin : gen_chi_x
        wire [P-1:0] chi_val = piv[gy][gx] ^ (~piv[gy][(gx+1)%5] & piv[gy][(gx+2)%5]);
        assign a_slice[gy][gx] = needs_chi_iota ? chi_val : src_val[gy][gx];
      end
    end
  endgenerate

  // iota: only lane (0,0), only the real bit positions, only on the
  // slice(s) that contain them for this PARALLEL_SLICES value.
  logic [P-1:0] a00_final;
  generate
    if (P >= 64) begin : gen_iota_wide
      // whole 64-bit lane in one slice: apply all 8 bit positions directly.
      wire [63:0] rc_full = {56'b0, rc8};
      assign a00_final = needs_chi_iota
          ? (a_slice[0][0] ^ {rc_full[7],
                               {(15){1'b0}}, rc_full[6],
                               {(15){1'b0}}, rc_full[5],
                               {(3){1'b0}},  rc_full[4],
                               {(3){1'b0}},  rc_full[3], rc_full[2], rc_full[1], rc_full[0]})
          : a_slice[0][0];
    end else begin : gen_iota_narrow
      localparam int unsigned BITPOS [0:7] = '{0, 1, 2, 3, 7, 15, 31, 63};
      logic [P-1:0] iota_mask;
      always_comb begin
        iota_mask = '0;
        for (int k = 0; k < 8; k = k + 1)
          if (ADDR_W'(BITPOS[k] / P) == slice_idx_reg)
            iota_mask[BITPOS[k] % P] = rc8[k];
      end
      assign a00_final = a_slice[0][0] ^ (needs_chi_iota ? iota_mask : '0);
    end
  endgenerate

  //----------------------------------------------------------------
  // theta (applied to a_slice, i.e. this cycle's chi+iota output --
  // needs_theta groups only): column parity Cs[x], then D[x] using the
  // carry register for the wraparound term (placeholder 0 on slice 0,
  // patched afterward -- see the ST_PATCH state below).
  //----------------------------------------------------------------
  logic [P-1:0] cs [0:4];
  generate
    for (gx = 0; gx < 5; gx = gx + 1) begin : gen_cs
      assign cs[gx] = (gx == 0 ? a00_final : a_slice[0][gx])
                     ^ a_slice[1][gx] ^ a_slice[2][gx] ^ a_slice[3][gx] ^ a_slice[4][gx];
    end
  endgenerate

  logic [P-1:0] d [0:4];
  generate
    for (gx = 0; gx < 5; gx = gx + 1) begin : gen_d
      localparam int unsigned XM1 = (gx + 4) % 5;
      localparam int unsigned XP1 = (gx + 1) % 5;
      logic [P-1:0] rotl_bits;
      always_comb begin
        rotl_bits[0] = carry_reg[XP1];
        for (int i = 1; i < P; i = i + 1)
          rotl_bits[i] = cs[XP1][i-1];
      end
      assign d[gx] = rotl_bits ^ cs[XM1];
    end
  endgenerate

  logic [P-1:0] theta_out [0:4][0:4];
  generate
    for (gy = 0; gy < 5; gy = gy + 1) begin : gen_theta_y
      for (gx = 0; gx < 5; gx = gx + 1) begin : gen_theta_x
        wire [P-1:0] a_here = (gy == 0 && gx == 0) ? a00_final : a_slice[gy][gx];
        assign theta_out[gy][gx] = needs_theta ? (a_here ^ d[gx]) : a_here;
      end
    end
  endgenerate

  //----------------------------------------------------------------
  // Write-back: group 0 and groups 0..KECCAK_ROUNDS-1 write theta_out to
  // the write buffer at slice_idx; the final group (KECCAK_ROUNDS, no
  // theta) writes a_slice (its chi+iota output, the actual permutation
  // result for this slice) directly into state_out instead.
  //
  // Patch (ST_PATCH, one cycle after a needs_theta group's last slice):
  // slice 0 was written using carry=0 as a placeholder for the z=0
  // wraparound term; now that the true carry is known (carry_reg, just
  // updated from the last slice's column parity), XOR bit 0 of slice 0
  // for every lane in column x by carry_reg[(x+1)%5]. Needs slice 0's
  // written value back, which isn't otherwise available combinationally
  // at this point -- latched into slice0_latch when it was written.
  //----------------------------------------------------------------
  logic [P-1:0] slice0_latch [0:4][0:4];
  logic [4:0]   patch_bit;   // patch_bit[x] = carry_reg[(x+1)%5]

  generate
    for (gx = 0; gx < 5; gx = gx + 1) begin : gen_patch_bit
      assign patch_bit[gx] = carry_reg[(gx+1)%5];
    end
  endgenerate

  wire sweep_write = (st_reg == ST_SWEEP) && needs_theta;
  wire patch_write = (st_reg == ST_PATCH);

  generate
    for (gy = 0; gy < 5; gy = gy + 1) begin : gen_wr_y
      for (gx = 0; gx < 5; gx = gx + 1) begin : gen_wr_x
        wire [P-1:0] patched = slice0_latch[gy][gx] ^ {{(P-1){1'b0}}, patch_bit[gx]};
        assign wr_data[0][gy][gx] = patch_write ? patched : theta_out[gy][gx];
        assign wr_data[1][gy][gx] = patch_write ? patched : theta_out[gy][gx];

        always_ff @(posedge clk)
          if (sweep_write && (slice_idx_reg == '0))
            slice0_latch[gy][gx] <= theta_out[gy][gx];
      end
    end
  endgenerate

  assign wr_en[0]   = (sweep_write || patch_write) && (buf_sel_write == 1'b0);
  assign wr_en[1]   = (sweep_write || patch_write) && (buf_sel_write == 1'b1);
  assign wr_addr[0] = patch_write ? '0 : slice_idx_reg;
  assign wr_addr[1] = patch_write ? '0 : slice_idx_reg;

  //----------------------------------------------------------------
  // state_out: accumulated synchronously from a_slice during the final
  // group's sweep (no separate "unload" cycles needed) -- valid the
  // cycle `done` pulses.
  //----------------------------------------------------------------
  logic [1599:0] state_out_reg;
  generate
    for (gy = 0; gy < 5; gy = gy + 1) begin : gen_out_y
      for (gx = 0; gx < 5; gx = gx + 1) begin : gen_out_x
        wire [P-1:0] out_val = (gy==0 && gx==0) ? a00_final : a_slice[gy][gx];
        always_ff @(posedge clk)
          if (st_reg == ST_SWEEP && is_final)
            state_out_reg[64*(5*gy+gx) + P*slice_idx_reg +: P] <= out_val;
      end
    end
  endgenerate
  assign state_out = state_out_reg;

  //----------------------------------------------------------------
  // FSM sequencing.
  //----------------------------------------------------------------
  logic done_reg;
  assign done = done_reg;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      st_reg        <= ST_IDLE;
      group_idx_reg <= '0;
      slice_idx_reg <= '0;
      carry_reg     <= '0;
      done_reg      <= 1'b0;
    end else begin
      done_reg <= 1'b0;
      case (st_reg)
        ST_IDLE: begin
          if (start) begin
            st_reg        <= ST_SWEEP;
            group_idx_reg <= '0;
            slice_idx_reg <= '0;
            carry_reg     <= '0;
          end
        end

        ST_SWEEP: begin
          for (int cx = 0; cx < 5; cx = cx + 1)
            carry_reg[cx] <= cs[cx][P-1];

          if (last_slice) begin
            if (needs_theta) begin
              st_reg <= ST_PATCH;
            end else begin
              // final group's sweep just finished -- state_out_reg holds
              // the complete permutation result as of this edge.
              st_reg   <= ST_IDLE;
              done_reg <= 1'b1;
            end
          end else begin
            slice_idx_reg <= slice_idx_reg + 1'b1;
          end
        end

        ST_PATCH: begin
          st_reg        <= ST_SWEEP;
          slice_idx_reg <= '0;
          group_idx_reg <= group_idx_reg + 1'b1;
          carry_reg     <= '0;   // next group's own slice-0 placeholder
        end

        default: st_reg <= ST_IDLE;
      endcase
    end
  end

endmodule
