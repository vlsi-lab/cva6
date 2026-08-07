/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Auth: Alessandra Dolmeta, Valeria Piscopo                                       //
// @ EDGE group, at VLSI-LAB, Politecnico di Torino                                //
// Date: July 2026                                                                 //
// Desc: Unified AES/Keccak accelerator top -- one controller, one shared state    //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

//  === Milestone 2 of the control-unification effort (see Milestone 1's
//      note in aes_core.sv and implementation.md): this used to instantiate
//      aes_core (its own FSM + 128-bit register) side by side with keccak_f
//      (keccak_cu's FSM + keccak_dp's own 1600-bit register), joined only
//      by a `sel` mux and a keccak_busy_reg pulse-to-level adapter -- two
//      separate controllers, two separate state registers, never sharing
//      anything. Now there is ONE FSM here (states below) and ONE shared
//      1600-bit register (`state_reg`, typed `k_state` from pkg_keccak.sv):
//      AES's 128-bit working block lives in state_reg[0][0]/state_reg[0][1]
//      (two of Keccak's 25 lanes), Keccak's permutation uses all 25 --
//      `sel` already makes the two mutually exclusive, so nothing is ever
//      aliased. `aes_key_mem`/`aes_encipher_datapath`/`aes_decipher_block`/
//      `aes_sbox` (the same pure-datapath modules aes_core.sv uses) and
//      `keccak_round`/`keccak_round_constants_gen` (the same combinational
//      per-round transform keccak_dp.sv used) are driven directly from this
//      one controller -- keccak_f.sv/keccak_cu.sv/keccak_dp.sv are no
//      longer instantiated anywhere in this design (retired, see
//      implementation.md).
//
//      aes_core.sv itself is untouched and still works standalone (its own
//      FSM/register, still exercised by tb_aes_core.cpp) -- this module
//      just doesn't build on top of it anymore, since sharing a register
//      with Keccak requires owning the AES datapath's storage directly
//      rather than through aes_core's opaque `init`/`next`/`ready` boundary.
//
//  === v3: on-the-fly key expansion (see aes_key_mem.sv's and aes_core.sv's
//      header comments) -- this module's AES-side control (CTRL_IDLE/
//      CTRL_KEY_GEN/CTRL_BLOCK_INIT/CTRL_BLOCK_SBOX/CTRL_BLOCK_MAIN) mirrors
//      aes_core.sv's identically: `init` is a no-op, CTRL_KEY_GEN is
//      decrypt's up-front forward walk, encrypt seeds+interleaves through
//      CTRL_BLOCK_INIT/SBOX, and CTRL_BLOCK_SBOX now has 5 sub-cycles (the
//      5th dedicated to the key-schedule step, since it needs the same
//      shared S-box the cipher's own SubBytes uses on the other 4).
//
//  === v4: configurable S-box (see aes_sbox.sv/aes_sbox_pkg.sv/aes_core.sv's
//      header comments) -- this module's sbox transaction sequencer
//      (`sbox_busy_reg` below) mirrors aes_core.sv's exactly: issue once
//      (`sbox_req_valid`), go quiet for pure-wait cycles, then re-present
//      the identical request on the cycle `sbox_rsp_valid` fires, which
//      both recomputes it (harmlessly) and commits it now that new_sboxw
//      is valid. See aes_core.sv's header comment for why the request must
//      NOT be committed on the issue cycle (round_key_update stays low
//      then -- only round_key_reverse is asserted, for tmp_sboxw's sake).
//
//  External port list and handshake are bit-for-bit unchanged from before
//  (that's what lets every existing testbench -- tb_keccak_aes_k_top.cpp
//  and all ten app-level tests -- verify this with zero test-code changes):
//
//  Usage (sel=SEL_AES):
//      1. set sel/encdec/keylen, write key, pulse init, poll ready
//      2. write block, pulse next, poll ready/result_valid, read result
//
//  Usage (sel=SEL_KECCAK):
//      1. set sel, write keccak_din
//      2. pulse next (init/encdec/keylen ignored), poll ready/keccak_done,
//         read keccak_dout

`default_nettype none

import pkg_keccak::k_state;
import aes_sbox_pkg::AES_SBOX_IMPL_SERIAL_ROM;

module keccak_aes_k_top #(
                parameter int unsigned SBOX_IMPL = AES_SBOX_IMPL_SERIAL_ROM
               )(
                input  wire            clk,
                input  wire            reset_n,
                input  wire            zeroize,   //  scrub state_reg + the AES key schedule to 0;
                                                   //  bounded at 1 cycle, takes priority over any
                                                   //  in-flight operation (ready stays low throughout)

                input  wire            sel,       //  0 = keccak, 1 = aes
                input  wire            encdec,    //  aes only: 1=encrypt, 0=decrypt
                input  wire            keylen,    //  aes only: 0=128-bit, 1=256-bit

                input  wire            init,      //  aes only: start key schedule
                input  wire            next,      //  aes: run block: keccak: start permute
                output wire            ready,     //  1 = idle / operation complete

                input  wire [255 : 0]  key,           //  aes only
                input  wire [127 : 0]  block,         //  aes only
                output wire [127 : 0]  result,        //  aes only
                output wire            result_valid,  //  aes only

                input  wire [1599 : 0] keccak_din,    //  keccak only
                output wire [1599 : 0] keccak_dout,   //  keccak only
                output wire            keccak_done    //  keccak only: 1-cycle done pulse
               );

  localparam SEL_KECCAK = 1'b0;
  localparam SEL_AES    = 1'b1;

  localparam AES128_ROUNDS = 5'd10;
  localparam AES256_ROUNDS = 5'd14;

  localparam NO_UPDATE    = 3'h0;
  localparam INIT_UPDATE  = 3'h1;
  localparam SBOX_UPDATE  = 3'h2;
  localparam MAIN_UPDATE  = 3'h3;
  localparam FINAL_UPDATE = 3'h4;

  localparam CTRL_IDLE          = 3'h0;
  localparam CTRL_KEY_GEN       = 3'h1;
  localparam CTRL_BLOCK_INIT    = 3'h2;
  localparam CTRL_BLOCK_SBOX    = 3'h3;
  localparam CTRL_BLOCK_MAIN    = 3'h4;
  localparam CTRL_KECCAK_ROUND  = 3'h5;
  localparam CTRL_ZEROIZE       = 3'h6;


  //----------------------------------------------------------------
  // Registers.
  //----------------------------------------------------------------
  reg [2 : 0] core_ctrl_reg;
  reg [2 : 0] core_ctrl_new;
  reg         core_ctrl_we;

  // Shared between AES's key_mem[]/block round-index (0..14) and Keccak's
  // round index (0..23) -- the two never run at the same time (`sel`).
  reg [4 : 0] round_ctr_reg;
  reg [4 : 0] round_ctr_new;
  reg         round_ctr_we;

  // AES-only: SBOX phase's word-serial sub-counter (0..3), plus, v3, a 5th
  // sub-cycle (4) dedicated to the interleaved key-schedule step -- see
  // aes_key_mem.sv's header comment.
  reg [2 : 0] sword_ctr_reg;
  reg [2 : 0] sword_ctr_new;
  reg         sword_ctr_we;

  reg         ready_reg;
  reg         ready_new;
  reg         ready_we;

  reg         result_valid_reg;
  reg         result_valid_new;
  reg         result_valid_we;

  // v4: 1 = a sbox request has been issued and accepted, waiting for its
  // response -- gates whether the current CTRL_KEY_GEN/CTRL_BLOCK_SBOX
  // sub-step is allowed to complete (see core_ctrl below).
  reg         sbox_busy_reg;
  reg         sbox_busy_new;
  reg         sbox_busy_we;

  // Genuine one-cycle registered pulse (mirrors ready_reg/result_valid_reg's
  // timing exactly -- NOT combinationally re-derived from round_ctr_reg,
  // which reads 23 a cycle *before* the 24th/final round actually commits
  // to state_reg, one cycle too early for a "done" signal to fire on).
  reg         keccak_done_reg;
  reg         keccak_done_new;
  reg         keccak_done_we;

  // The one working-state register shared between AES (uses lanes (0,0)
  // and (0,1), i.e. 2 of the 25 64-bit lanes, as 4 32-bit words) and Keccak
  // (uses all 25 lanes) -- see file header comment.
  k_state state_reg;


  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  reg  [2 : 0] update_type;
  reg  [4 : 0] num_rounds;

  reg          state_load_din;     // pulse: state_reg <= keccak_din (Keccak start)
  reg          state_keccak_we;    // pulse: state_reg <= keccak_round_out (Keccak round)

  wire [127 : 0] old_block = {state_reg[0][0], state_reg[0][1]};

  wire [127 : 0] round_key0;
  wire [127 : 0] round_key1;
  reg            round_key_seed;
  reg            round_key_update;
  reg            round_key_reverse;

  // v3: every consumption point wants round_key1 (the current round's
  // key) except encrypt's round-0 AddRoundKey for AES-256, where the seed
  // pulse has just landed round 0's key in round_key0 instead (round 1's
  // key, already seeded alongside it, sits in round_key1) -- see
  // aes_key_mem.sv's header comment.
  wire round_key0_selected = encdec && keylen && (core_ctrl_reg == CTRL_BLOCK_INIT);
  wire [127 : 0] round_key = round_key0_selected ? round_key0 : round_key1;

  wire [31 : 0]  keymem_sboxw;
  wire [31 : 0]  enc_sboxw;
  wire [31 : 0]  dec_sboxw;
  wire [31 : 0]  new_sboxw;
  reg  [31 : 0]  muxed_sboxw;
  reg            sbox_inv;

  // v4: sbox request/response handshake -- see aes_sbox.sv's header
  // comment. rsp_ready is tied high: we never need to backpressure a
  // response we're actively waiting on.
  reg            sbox_req_valid;
  wire           sbox_req_ready;
  wire           sbox_rsp_valid;
  wire           sbox_rsp_ready = 1'b1;

  wire [127 : 0] enc_block_new;
  wire           enc_w0_we, enc_w1_we, enc_w2_we, enc_w3_we;
  wire [127 : 0] dec_block_new;
  wire           dec_w0_we, dec_w1_we, dec_w2_we, dec_w3_we;

  wire [127 : 0] muxed_block_new = encdec ? enc_block_new : dec_block_new;
  wire           muxed_w0_we     = encdec ? enc_w0_we     : dec_w0_we;
  wire           muxed_w1_we     = encdec ? enc_w1_we     : dec_w1_we;
  wire           muxed_w2_we     = encdec ? enc_w2_we     : dec_w2_we;
  wire           muxed_w3_we     = encdec ? enc_w3_we     : dec_w3_we;

  k_state        din_kstate;
  wire [7 : 0]   keccak_round_const;  // 8 bits: see keccak_round_constants_gen.sv
  k_state        keccak_round_out;


  //----------------------------------------------------------------
  // keccak_din -> k_state, and state_reg -> keccak_dout: lane L = 5y+x
  // occupies bits [64L+63 : 64L] of the flat 1600-bit vector, matching
  // keccak_dp.sv's original Dout-flattening convention exactly.
  //----------------------------------------------------------------
  genvar gy, gx;
  generate
    for (gy = 0; gy < 5; gy = gy + 1) begin : g_lane_y
      for (gx = 0; gx < 5; gx = gx + 1) begin : g_lane_x
        assign din_kstate[gy][gx]              = keccak_din[320*gy + 64*gx +: 64];
        assign keccak_dout[320*gy + 64*gx +: 64] = state_reg[gy][gx];
      end
    end
  endgenerate


  //----------------------------------------------------------------
  // Instantiations -- same AES datapath modules aes_core.sv uses, plus
  // Keccak's per-round transform and round-constant generator, all driven
  // directly by this module's own FSM instead of aes_core's or keccak_f's.
  //----------------------------------------------------------------
  aes_encipher_datapath enc_dp(
                               .update_type(update_type),
                               .sword_ctr(sword_ctr_reg[1 : 0]),  // datapath only ever sees 0..3

                               .block(block),
                               .old_block(old_block),
                               .round_key(round_key),

                               .sboxw(enc_sboxw),
                               .new_sboxw(new_sboxw),

                               .block_new(enc_block_new),
                               .block_w0_we(enc_w0_we),
                               .block_w1_we(enc_w1_we),
                               .block_w2_we(enc_w2_we),
                               .block_w3_we(enc_w3_we)
                              );

  aes_decipher_block dec_dp(
                            .update_type(update_type),
                            .sword_ctr(sword_ctr_reg[1 : 0]),  // datapath only ever sees 0..3

                            .block(block),
                            .old_block(old_block),
                            .round_key(round_key),

                            .sboxw(dec_sboxw),
                            .new_sboxw(new_sboxw),

                            .block_new(dec_block_new),
                            .block_w0_we(dec_w0_we),
                            .block_w1_we(dec_w1_we),
                            .block_w2_we(dec_w2_we),
                            .block_w3_we(dec_w3_we)
                           );

  aes_key_mem keymem(
                     .clk(clk),
                     .reset_n(reset_n),
                     .zeroize(zeroize),

                     .key(key),
                     .keylen(keylen),

                     .round(round_ctr_reg[3 : 0]),
                     .round_key_seed(round_key_seed),
                     .round_key_update(round_key_update),
                     .round_key_reverse(round_key_reverse),
                     .round_key0(round_key0),
                     .round_key1(round_key1),

                     .sboxw(keymem_sboxw),
                     .new_sboxw(new_sboxw)
                    );

  aes_sbox #(.SBOX_IMPL(SBOX_IMPL)) sbox_inst(
                     .clk(clk),
                     .reset_n(reset_n),

                     .req_valid(sbox_req_valid),
                     .req_ready(sbox_req_ready),
                     .inv(sbox_inv),
                     .sboxw(muxed_sboxw),

                     .rsp_valid(sbox_rsp_valid),
                     .rsp_ready(sbox_rsp_ready),
                     .new_sboxw(new_sboxw)
                    );

  keccak_round_constants_gen rc_gen(
                                    .round_number(round_ctr_reg),
                                    .round_constant_signal_out(keccak_round_const)
                                   );

  keccak_round kround(
                      .Round_in(state_reg),
                      .Round_constant_signal(keccak_round_const),
                      .Round_out(keccak_round_out)
                     );


  //----------------------------------------------------------------
  // Concurrent connectivity for ports etc.
  //----------------------------------------------------------------
  assign ready        = ready_reg;
  assign result       = old_block;
  assign result_valid = result_valid_reg;
  assign keccak_done  = keccak_done_reg;


  //----------------------------------------------------------------
  // reg_update
  //----------------------------------------------------------------
  always @ (posedge clk or negedge reset_n)
    begin: reg_update
      if (!reset_n)
        begin
          state_reg        <= '0;
          round_ctr_reg    <= 5'h0;
          sword_ctr_reg    <= 3'h0;
          result_valid_reg <= 1'b0;
          ready_reg        <= 1'b1;
          keccak_done_reg  <= 1'b0;
          core_ctrl_reg    <= CTRL_IDLE;
          sbox_busy_reg    <= 1'b0;
        end
      else if (zeroize)
        begin
          // Same scrub as reset for the shared working state, but
          // synchronous and caller-triggered; core_ctrl_reg still moves to
          // CTRL_ZEROIZE via the normal core_ctrl_we/new path below (driven
          // by core_ctrl's own top-priority `if (zeroize)` check).
          state_reg <= '0;

          if (round_ctr_we)
            round_ctr_reg <= round_ctr_new;

          if (sword_ctr_we)
            sword_ctr_reg <= sword_ctr_new;

          if (result_valid_we)
            result_valid_reg <= result_valid_new;

          if (ready_we)
            ready_reg <= ready_new;

          if (keccak_done_we)
            keccak_done_reg <= keccak_done_new;

          if (core_ctrl_we)
            core_ctrl_reg <= core_ctrl_new;

          // v4: abort any sbox transaction that was outstanding when
          // zeroize hit -- see aes_core.sv's identical reg_update comment.
          sbox_busy_reg <= 1'b0;
        end
      else
        begin
          if (state_load_din)
            state_reg <= din_kstate;
          else if (state_keccak_we)
            state_reg <= keccak_round_out;
          else
            begin
              if (muxed_w0_we)
                state_reg[0][0][63 : 32] <= muxed_block_new[127 : 096];

              if (muxed_w1_we)
                state_reg[0][0][31 : 00] <= muxed_block_new[095 : 064];

              if (muxed_w2_we)
                state_reg[0][1][63 : 32] <= muxed_block_new[063 : 032];

              if (muxed_w3_we)
                state_reg[0][1][31 : 00] <= muxed_block_new[031 : 000];
            end

          if (round_ctr_we)
            round_ctr_reg <= round_ctr_new;

          if (sword_ctr_we)
            sword_ctr_reg <= sword_ctr_new;

          if (result_valid_we)
            result_valid_reg <= result_valid_new;

          if (ready_we)
            ready_reg <= ready_new;

          if (keccak_done_we)
            keccak_done_reg <= keccak_done_new;

          if (core_ctrl_we)
            core_ctrl_reg <= core_ctrl_new;

          if (sbox_busy_we)
            sbox_busy_reg <= sbox_busy_new;
        end
    end // reg_update


  //----------------------------------------------------------------
  // sbox_mux
  //
  // Controls which of the key memory, encipher, or decipher datapath
  // gets access to the one shared (forward + inverse) sbox this cycle.
  // (Unused/don't-care during Keccak phases -- nothing reads new_sboxw
  // then, since update_type stays NO_UPDATE.)
  // v3: the key schedule now also needs it during CTRL_BLOCK_SBOX's
  // dedicated 5th sub-cycle (sword_ctr_reg==4), not just CTRL_KEY_GEN --
  // see aes_key_mem.sv's header comment.
  //----------------------------------------------------------------
  always @*
    begin : sbox_mux
      if ((core_ctrl_reg == CTRL_KEY_GEN) ||
          (core_ctrl_reg == CTRL_BLOCK_SBOX && sword_ctr_reg == 3'h4))
        begin
          muxed_sboxw = keymem_sboxw;
          sbox_inv    = 1'b0;  // key schedule always uses the forward S-box, both directions
        end
      else
        begin
          muxed_sboxw = encdec ? enc_sboxw : dec_sboxw;
          sbox_inv    = !encdec;
        end
    end // sbox_mux


  //----------------------------------------------------------------
  // core_ctrl
  //
  // The single FSM controlling AES key expansion, AES encipherment/
  // decipherment, and the Keccak-f[1600] permutation -- replacing
  // aes_core's own unified FSM (Milestone 1) plus keccak_cu's/keccak_dp's
  // separate sequencing (this milestone).
  //----------------------------------------------------------------
  always @*
    begin : core_ctrl
      core_ctrl_new    = CTRL_IDLE;
      core_ctrl_we     = 1'b0;
      round_ctr_new    = 5'h0;
      round_ctr_we     = 1'b0;
      sword_ctr_new    = 3'h0;
      sword_ctr_we     = 1'b0;
      ready_new        = 1'b0;
      ready_we         = 1'b0;
      result_valid_new = 1'b0;
      result_valid_we  = 1'b0;
      round_key_seed    = 1'b0;
      round_key_update  = 1'b0;
      round_key_reverse = 1'b0;
      update_type      = NO_UPDATE;
      state_load_din   = 1'b0;
      state_keccak_we  = 1'b0;
      keccak_done_new  = 1'b0;
      keccak_done_we   = 1'b1;  // clear every cycle by default -- 1-cycle pulse
      sbox_req_valid   = 1'b0;
      sbox_busy_new    = sbox_busy_reg;
      sbox_busy_we     = 1'b0;

      num_rounds = (keylen == 1'b1) ? AES256_ROUNDS : AES128_ROUNDS;

      if (zeroize)
        begin
          // Top priority from any state -- aborts any in-flight operation,
          // ready stays low until zeroize is released.
          ready_new     = 1'b0;
          ready_we      = 1'b1;
          core_ctrl_new = CTRL_ZEROIZE;
          core_ctrl_we  = 1'b1;
        end
      else
      case (core_ctrl_reg)
        CTRL_ZEROIZE:
          begin
            // Reached only once zeroize has been released (the `if
            // (zeroize)` branch above takes over unconditionally while it's
            // held) -- one cycle back to idle.
            ready_new     = 1'b1;
            ready_we      = 1'b1;
            core_ctrl_new = CTRL_IDLE;
            core_ctrl_we  = 1'b1;
          end

        CTRL_IDLE:
          begin
            if (init && (sel == SEL_AES))
              begin
                // v3: init no longer does any key-schedule work (see
                // aes_key_mem.sv/aes_core.sv header comments) -- ready is
                // already 1, so there's nothing to do here at all.
              end
            else if (next && (sel == SEL_AES))
              begin
                round_ctr_new    = 5'h0;
                round_ctr_we     = 1'b1;
                ready_new        = 1'b0;
                ready_we         = 1'b1;
                result_valid_new = 1'b0;
                result_valid_we  = 1'b1;

                if (encdec)
                  begin
                    // Encrypt: seed the schedule from the raw key now, so
                    // it's already there by the time CTRL_BLOCK_INIT
                    // consumes it next cycle -- then interleave the rest
                    // forward, one round key per round, in CTRL_BLOCK_SBOX.
                    round_key_seed = 1'b1;
                    core_ctrl_new  = CTRL_BLOCK_INIT;
                  end
                else
                  begin
                    // Decrypt: walk the schedule forward first (repurposed
                    // CTRL_KEY_GEN, below) to reach the last round key --
                    // its own round_ctr_reg==0 cycle fires the seed.
                    core_ctrl_new = CTRL_KEY_GEN;
                  end

                core_ctrl_we = 1'b1;
              end
            else if (next && (sel == SEL_KECCAK))
              begin
                state_load_din = 1'b1;
                round_ctr_new  = 5'h0;
                round_ctr_we   = 1'b1;
                ready_new      = 1'b0;
                ready_we       = 1'b1;
                core_ctrl_new  = CTRL_KECCAK_ROUND;
                core_ctrl_we   = 1'b1;
              end
          end

        CTRL_KEY_GEN:
          begin
            // Decrypt-only now (v3): an up-front forward walk from the raw
            // key to the last round key, same cycle cost as v2's init
            // (num_rounds+1 cycles: one seed + num_rounds forward steps) --
            // v4: "cycle cost" now means num_rounds sbox round-trips, not
            // flat cycles (see aes_core.sv's identical state for the full
            // explanation).
            if (round_ctr_reg == 5'h0)
              begin
                // Seed: no sbox needed, completes in 1 cycle as before.
                round_key_seed = 1'b1;
                round_ctr_new  = round_ctr_reg + 1'b1;
                round_ctr_we   = 1'b1;
              end
            else if (keylen && (round_ctr_reg == 5'h1))
              begin
                // AES-256's round 1 key is the raw key's lower half,
                // already seeded above -- nothing to compute, 1 cycle.
                round_ctr_new = round_ctr_reg + 1'b1;
                round_ctr_we  = 1'b1;
              end
            else
              begin
                // Needs a forward sbox round-trip. round_key_reverse (only
                // -- NOT round_key_update) is asserted on the issue cycle;
                // round_key_update joins it only on the complete cycle,
                // once new_sboxw is valid -- see aes_core.sv's identical
                // state and aes_key_mem.sv's header comment for why.
                round_key_reverse = 1'b0;

                if (!sbox_busy_reg)
                  begin
                    sbox_req_valid = 1'b1;
                    sbox_busy_new  = 1'b1;
                    sbox_busy_we   = 1'b1;
                  end
                else if (sbox_rsp_valid)
                  begin
                    round_key_update = 1'b1;
                    round_ctr_new    = round_ctr_reg + 1'b1;
                    round_ctr_we     = 1'b1;
                    sbox_busy_new    = 1'b0;
                    sbox_busy_we     = 1'b1;
                  end
                // else: still waiting on the response, nothing else fires.
              end

            if (round_ctr_we && round_ctr_reg == num_rounds)
              begin
                // This cycle's completion (seed/skip/sbox-response, whichever
                // fired above) just landed round num_rounds's key -- go
                // straight into block processing (no ready pulse in
                // between; decrypt stays busy for the whole operation).
                round_ctr_new = num_rounds;
                core_ctrl_new = CTRL_BLOCK_INIT;
                core_ctrl_we  = 1'b1;
              end
          end

        CTRL_BLOCK_INIT:
          begin
            update_type   = INIT_UPDATE;
            sword_ctr_new = 3'h0;
            sword_ctr_we  = 1'b1;

            if (encdec)
              begin
                round_ctr_new = round_ctr_reg + 1'b1;
                round_ctr_we  = 1'b1;
              end

            core_ctrl_new = CTRL_BLOCK_SBOX;
            core_ctrl_we  = 1'b1;
          end

        CTRL_BLOCK_SBOX:
          begin
            // v3: 5 sub-cycles now, not 4 -- sword_ctr_reg 0..3 are the
            // cipher's own word-serial SBOX substitution; the new 5th
            // (==4) is a dedicated cycle for this round's key-schedule
            // step (forward for encrypt, backward for decrypt), which
            // also needs the one shared S-box and can't run on the SAME
            // cycle the cipher itself is using it -- see aes_key_mem.sv's
            // header comment. v4: every sub-cycle except the AES-256
            // round-1 skip now needs an sbox round-trip (possibly
            // multi-cycle) instead of completing in 1 cycle flat -- see
            // aes_core.sv's identical state for the full explanation.
            if (sword_ctr_reg == 3'h4 && encdec && keylen && (round_ctr_reg == 5'h1))
              begin
                // AES-256's round 1 key was already seeded whole -- no
                // sbox needed, 1 cycle straight through to CTRL_BLOCK_MAIN.
                sword_ctr_new = sword_ctr_reg + 1'b1;
                sword_ctr_we  = 1'b1;
                core_ctrl_new = CTRL_BLOCK_MAIN;
                core_ctrl_we  = 1'b1;
              end
            else if (!sbox_busy_reg)
              begin
                // Issue: present this sub-cycle's request. sword_ctr<4
                // (cipher SubBytes/InvSubBytes) can safely use
                // update_type=SBOX_UPDATE here (the eventual commit only
                // depends on new_sboxw, not old_block). sword_ctr==4 (key
                // schedule) asserts ONLY round_key_reverse, NOT
                // round_key_update -- see aes_core.sv's identical state.
                if (sword_ctr_reg < 3'h4)
                  update_type = SBOX_UPDATE;
                else
                  round_key_reverse = encdec ? 1'b0 : 1'b1;

                sbox_req_valid = 1'b1;
                sbox_busy_new  = 1'b1;
                sbox_busy_we   = 1'b1;
              end
            else if (sbox_rsp_valid)
              begin
                // Complete: re-present the SAME request (old_block/
                // prev_key0/1_reg unchanged since no write happened during
                // the wait) so the datapath/key-mem recompute the
                // identical thing, this time actually committing it now
                // that new_sboxw is valid.
                if (sword_ctr_reg < 3'h4)
                  update_type = SBOX_UPDATE;
                else if (encdec)
                  begin
                    round_key_update  = 1'b1;
                    round_key_reverse = 1'b0;
                  end
                else
                  begin
                    round_key_update  = 1'b1;
                    round_key_reverse = 1'b1;
                  end

                sword_ctr_new = sword_ctr_reg + 1'b1;
                sword_ctr_we  = 1'b1;
                sbox_busy_new = 1'b0;
                sbox_busy_we  = 1'b1;

                if (sword_ctr_reg == 3'h4)
                  begin
                    if (!encdec)
                      begin
                        round_ctr_new = round_ctr_reg - 1'b1;
                        round_ctr_we  = 1'b1;
                      end

                    core_ctrl_new = CTRL_BLOCK_MAIN;
                    core_ctrl_we  = 1'b1;
                  end
              end
            // else: still waiting on the response, nothing else fires --
            // update_type/round_key_update stay at their defaults (0), so
            // old_block/prev_key0/1_reg stay stable and uncorrupted.
          end

        CTRL_BLOCK_MAIN:
          begin
            sword_ctr_new = 3'h0;
            sword_ctr_we  = 1'b1;

            if (encdec)
              begin
                if (round_ctr_reg < num_rounds)
                  begin
                    update_type   = MAIN_UPDATE;
                    round_ctr_new = round_ctr_reg + 1'b1;
                    round_ctr_we  = 1'b1;
                    core_ctrl_new = CTRL_BLOCK_SBOX;
                    core_ctrl_we  = 1'b1;
                  end
                else
                  begin
                    update_type      = FINAL_UPDATE;
                    ready_new        = 1'b1;
                    ready_we         = 1'b1;
                    result_valid_new = 1'b1;
                    result_valid_we  = 1'b1;
                    core_ctrl_new    = CTRL_IDLE;
                    core_ctrl_we     = 1'b1;
                  end
              end
            else
              begin
                if (round_ctr_reg > 0)
                  begin
                    update_type   = MAIN_UPDATE;
                    core_ctrl_new = CTRL_BLOCK_SBOX;
                    core_ctrl_we  = 1'b1;
                  end
                else
                  begin
                    update_type      = FINAL_UPDATE;
                    ready_new        = 1'b1;
                    ready_we         = 1'b1;
                    result_valid_new = 1'b1;
                    result_valid_we  = 1'b1;
                    core_ctrl_new    = CTRL_IDLE;
                    core_ctrl_we     = 1'b1;
                  end
              end
          end

        CTRL_KECCAK_ROUND:
          begin
            state_keccak_we = 1'b1;
            round_ctr_new   = round_ctr_reg + 1'b1;
            round_ctr_we    = 1'b1;

            if (round_ctr_reg == 5'd23)
              begin
                // This cycle's state_keccak_we commits the 24th/final round
                // (RC[23]) into state_reg on the upcoming edge -- ready_reg
                // and keccak_done_reg land on that exact same edge, so both
                // become visible in lockstep with the finished result.
                ready_new       = 1'b1;
                ready_we        = 1'b1;
                keccak_done_new = 1'b1;
                keccak_done_we  = 1'b1;
                core_ctrl_new   = CTRL_IDLE;
                core_ctrl_we    = 1'b1;
              end
          end

        default:
          begin
          end
      endcase // case (core_ctrl_reg)
    end // core_ctrl

endmodule // keccak_aes_k_top

//======================================================================
// EOF keccak_aes_k_top.sv
//======================================================================
