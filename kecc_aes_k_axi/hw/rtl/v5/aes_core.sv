//  Reference: unmodified round-transform math from secworks/aes
//  (see https://github.com/secworks/aesaes); control logic rewritten here.
//
//  Milestone 1 of the AES/Keccak coprocessor control-unification effort
//  (see /home/aledolme/.claude/plans/happy-jingling-yeti.md and
//  implementation.md): what used to be four separate FSMs --
//  aes_key_mem's key_mem_ctrl, aes_encipher_block's encipher_ctrl,
//  aes_decipher_block's decipher_ctrl, and this module's own thin
//  IDLE/INIT/NEXT dispatcher -- are now ONE FSM here. aes_key_mem.sv lost
//  its own FSM (round/round_key_update are now inputs it's simply told);
//  aes_decipher_block.sv lost its FSM AND its own block/sword/round
//  registers (now pure combinational, driven by the shared block register
//  below); aes_encipher_block.sv is untouched (still used, FSM and all, by
//  aes_enc128_core.sv) -- its replacement here is aes_encipher_datapath.sv,
//  the same round-transform math with the FSM/registers likewise stripped.
//
//  Encipher and decipher no longer keep their own separate 128-bit working
//  registers -- since `encdec` already makes them mutually exclusive, this
//  core owns ONE shared block register (block_w0..w3_reg) that whichever
//  datapath is selected reads from and writes into.
//
//  aes_sbox.sv is now one physical table (forward + inverse behind an `inv`
//  select) shared by key expansion, encipherment, and decipherment --
//  arbitrated below exactly like the old sbox_mux, just extended one more
//  way and carrying the extra `inv` bit for decrypt.
//
//  v3: on-the-fly key expansion (see aes_key_mem.sv's header comment) --
//  CTRL_KEY_GEN is now decrypt-only (an up-front forward walk to reach the
//  last round key, entered from `next`+!encdec instead of from `init`).
//  `init` no longer does any key-schedule work at all -- ready stays 1
//  throughout, zero added latency. Encrypt seeds the schedule from the raw
//  key once per block (CTRL_IDLE's `next`+encdec transition, landing
//  before CTRL_BLOCK_INIT consumes it) and interleaves one forward
//  round-key step per round into that round's 4 idle-for-keygen SBOX
//  cycles (CTRL_BLOCK_SBOX). Decrypt's own per-round walk runs backward
//  the same way, one round key recovered per round via aes_key_mem's
//  algebraic inversion. Total decrypt latency is unchanged from v2 (the
//  up-front walk costs the same num_rounds+1 cycles `init` used to);
//  encrypt drops that phase entirely.
//
//  v4: the shared aes_sbox is no longer 0-cycle combinational (see
//  aes_sbox.sv/aes_sbox_pkg.sv -- SBOX_IMPL picks a 4-cycle serial ROM, a
//  1-cycle dual-port ROM, or a 1-cycle Boyar-Peralta network). Every place
//  that used to just read `new_sboxw` combinationally the same cycle
//  (CTRL_BLOCK_SBOX's 5 sub-cycles, CTRL_KEY_GEN's per-round forward walk)
//  now goes through a small request/response sequencer (`sbox_busy_reg`
//  below): assert the request once (`sbox_req_valid`, guaranteed accepted
//  the same cycle since we never issue while already waiting on one), then
//  go quiet (`update_type`/`round_key_update` back to their defaults) for
//  any pure-wait cycles, and re-assert the SAME request only on the cycle
//  `sbox_rsp_valid` fires, which both recomputes it (harmlessly, from the
//  still-untouched old_block/prev_key0/1_reg) and commits it, now that
//  new_sboxw is valid. Holding update_type/round_key_update asserted for
//  the *whole* wait was tried first and is wrong: it write-enables
//  old_block/prev_key0/1_reg every wait cycle with whatever `new_sboxw`
//  happens to be mid-transaction, and since those same registers feed
//  back into the next cycle's sbox request, that corrupts the request
//  that's still in flight. `aes_key_mem.sv` and the encipher/decipher
//  datapaths needed zero changes for the fixed version -- see aes_sbox.sv's
//  header comment for why.

//======================================================================
//
// aes_core.sv
// ----------
// The AES core. This core supports key size of 128, and 256 bits.
//
//
// Author: Joachim Strombergson
// Copyright (c) 2013, 2014, Secworks Sweden AB
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or
// without modification, are permitted provided that the following
// conditions are met:
//
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in
//    the documentation and/or other materials provided with the
//    distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
// FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
// COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
// BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
// STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//======================================================================

`default_nettype none

import aes_sbox_pkg::AES_SBOX_IMPL_SERIAL_ROM;

module aes_core #(
                   parameter int unsigned SBOX_IMPL = AES_SBOX_IMPL_SERIAL_ROM
                  )(
                input wire            clk,
                input wire            reset_n,
                input wire            zeroize,  //  scrub the key schedule + working block to 0;
                                                 //  bounded at 1 cycle, takes priority over any
                                                 //  in-flight operation (ready stays low throughout)

                input wire            encdec,
                input wire            init,
                input wire            next,
                output wire           ready,

                input wire [255 : 0]  key,
                input wire            keylen,

                input wire [127 : 0]  block,
                output wire [127 : 0] result,
                output wire           result_valid
               );


  //----------------------------------------------------------------
  // Internal constant and parameter definitions.
  //----------------------------------------------------------------
  localparam AES128_ROUNDS = 4'ha;
  localparam AES256_ROUNDS = 4'he;

  localparam NO_UPDATE    = 3'h0;
  localparam INIT_UPDATE  = 3'h1;
  localparam SBOX_UPDATE  = 3'h2;
  localparam MAIN_UPDATE  = 3'h3;
  localparam FINAL_UPDATE = 3'h4;

  localparam CTRL_IDLE       = 3'h0;
  localparam CTRL_KEY_GEN    = 3'h1;
  localparam CTRL_BLOCK_INIT = 3'h2;
  localparam CTRL_BLOCK_SBOX = 3'h3;
  localparam CTRL_BLOCK_MAIN = 3'h4;
  localparam CTRL_ZEROIZE    = 3'h5;


  //----------------------------------------------------------------
  // Registers including update variables and write enable.
  //----------------------------------------------------------------
  reg [2 : 0] core_ctrl_reg;
  reg [2 : 0] core_ctrl_new;
  reg         core_ctrl_we;

  reg [3 : 0] round_ctr_reg;   // shared: key_mem[] write index during key-gen,
                                // read index during block processing
  reg [3 : 0] round_ctr_new;
  reg         round_ctr_we;

  // Shared between encipher's/decipher's SBOX phase (values 0..3, one cipher
  // word-substitution per cycle) and, v3, a 5th sub-cycle (value 4) giving
  // the interleaved key-schedule step its own turn at the shared S-box --
  // see CTRL_BLOCK_SBOX below and aes_key_mem.sv's header comment.
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
  // sub-step is allowed to complete (see aes_core_ctrl below).
  reg         sbox_busy_reg;
  reg         sbox_busy_new;
  reg         sbox_busy_we;

  // The one working-block register shared between encipher and decipher
  // (mutually exclusive via `encdec`) -- Milestone 2 widens the equivalent
  // storage to also cover Keccak's 1600-bit state.
  reg [31 : 0] block_w0_reg;
  reg [31 : 0] block_w1_reg;
  reg [31 : 0] block_w2_reg;
  reg [31 : 0] block_w3_reg;


  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  reg  [2 : 0] update_type;

  reg  [3 : 0] num_rounds;

  wire [127 : 0] old_block = {block_w0_reg, block_w1_reg, block_w2_reg, block_w3_reg};

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


  //----------------------------------------------------------------
  // Instantiations.
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

                     .round(round_ctr_reg),
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


  //----------------------------------------------------------------
  // Concurrent connectivity for ports etc.
  //----------------------------------------------------------------
  assign ready        = ready_reg;
  assign result       = old_block;
  assign result_valid = result_valid_reg;


  //----------------------------------------------------------------
  // reg_update
  //
  // Update functionality for all registers in the core.
  // All registers are positive edge triggered with asynchronous
  // active low reset. All registers have write enable.
  //----------------------------------------------------------------
  always @ (posedge clk or negedge reset_n)
    begin: reg_update
      if (!reset_n)
        begin
          block_w0_reg     <= 32'h0;
          block_w1_reg     <= 32'h0;
          block_w2_reg     <= 32'h0;
          block_w3_reg     <= 32'h0;
          round_ctr_reg    <= 4'h0;
          sword_ctr_reg    <= 3'h0;
          result_valid_reg <= 1'b0;
          ready_reg        <= 1'b1;
          core_ctrl_reg    <= CTRL_IDLE;
          sbox_busy_reg    <= 1'b0;
        end
      else if (zeroize)
        begin
          // Same scrub as reset for the sensitive working block, but
          // synchronous and caller-triggered; core_ctrl_reg still moves to
          // CTRL_ZEROIZE via the normal core_ctrl_we/new path below (driven
          // by aes_core_ctrl's own top-priority `if (zeroize)` check).
          block_w0_reg <= 32'h0;
          block_w1_reg <= 32'h0;
          block_w2_reg <= 32'h0;
          block_w3_reg <= 32'h0;

          if (round_ctr_we)
            round_ctr_reg <= round_ctr_new;

          if (sword_ctr_we)
            sword_ctr_reg <= sword_ctr_new;

          if (result_valid_we)
            result_valid_reg <= result_valid_new;

          if (ready_we)
            ready_reg <= ready_new;

          if (core_ctrl_we)
            core_ctrl_reg <= core_ctrl_new;

          // v4: abort any sbox transaction that was outstanding when
          // zeroize hit -- the sbox itself self-recovers on its own (it'll
          // still assert rsp_valid once done and see rsp_ready=1, clearing
          // itself), but our own bookkeeping must forget about it too, or
          // the next real operation would wait forever for a response it
          // already silently consumed.
          sbox_busy_reg <= 1'b0;
        end
      else
        begin
          if (muxed_w0_we)
            block_w0_reg <= muxed_block_new[127 : 096];

          if (muxed_w1_we)
            block_w1_reg <= muxed_block_new[095 : 064];

          if (muxed_w2_we)
            block_w2_reg <= muxed_block_new[063 : 032];

          if (muxed_w3_we)
            block_w3_reg <= muxed_block_new[031 : 000];

          if (round_ctr_we)
            round_ctr_reg <= round_ctr_new;

          if (sword_ctr_we)
            sword_ctr_reg <= sword_ctr_new;

          if (result_valid_we)
            result_valid_reg <= result_valid_new;

          if (ready_we)
            ready_reg <= ready_new;

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
  // aes_core_ctrl
  //
  // The single FSM controlling key expansion and block processing
  // (encipher and decipher), replacing what used to be four separate
  // FSMs (see file header comment).
  //----------------------------------------------------------------
  always @*
    begin : aes_core_ctrl
      core_ctrl_new    = CTRL_IDLE;
      core_ctrl_we      = 1'b0;
      round_ctr_new    = 4'h0;
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
            if (init)
              begin
                // v3: init no longer does any key-schedule work (see
                // aes_key_mem.sv/file header) -- ready is already 1, so
                // there's nothing to do here at all.
              end
            else if (next)
              begin
                round_ctr_new    = 4'h0;
                round_ctr_we     = 1'b1;
                ready_new        = 1'b0;
                ready_we         = 1'b1;
                result_valid_new = 1'b0;
                result_valid_we  = 1'b1;

                if (encdec)
                  begin
                    // Encrypt: seed the schedule from the raw key now, so
                    // it's already in prev_key1_reg (and prev_key0_reg for
                    // AES-256) by the time CTRL_BLOCK_INIT consumes it next
                    // cycle -- then interleave the rest forward, one round
                    // key per round, in CTRL_BLOCK_SBOX below.
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
          end

        CTRL_KEY_GEN:
          begin
            // Decrypt-only now (v3): an up-front forward walk from the raw
            // key to the last round key, same cycle cost as v2's init
            // (num_rounds+1 cycles: one seed + num_rounds forward steps) --
            // v4: "cycle cost" now means num_rounds sbox round-trips, not
            // flat cycles, since round 0's seed needs no sbox but every
            // other round's forward step does (see the sequencer note in
            // the file header comment).
            if (round_ctr_reg == 4'h0)
              begin
                // Seed: no sbox needed, completes in 1 cycle as before.
                round_key_seed = 1'b1;
                round_ctr_new  = round_ctr_reg + 1'b1;
                round_ctr_we   = 1'b1;
              end
            else if (keylen && (round_ctr_reg == 4'h1))
              begin
                // AES-256's round 1 key is the raw key's lower half,
                // already seeded above -- nothing to compute, 1 cycle.
                round_ctr_new = round_ctr_reg + 1'b1;
                round_ctr_we  = 1'b1;
              end
            else
              begin
                // Needs a forward sbox round-trip. round_key_reverse (only
                // -- NOT round_key_update) is asserted on the issue cycle,
                // so aes_key_mem presents the right tmp_sboxw without
                // committing anything; round_key_update joins it only on
                // the complete cycle, once new_sboxw is valid. Critically,
                // prev_key0/1_reg/rcon_reg are NEVER written between issue
                // and completion (see aes_key_mem.sv's header comment) --
                // committing on the issue cycle too (as an earlier version
                // of this sequencer did) would corrupt the very registers
                // the complete cycle's recurrence reads again.
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
                // Matches old encipher_ctrl's CTRL_INIT: round_ctr_inc=1.
                round_ctr_new = round_ctr_reg + 1'b1;
                round_ctr_we  = 1'b1;
              end
            // Decrypt: round_ctr unchanged here, matches old decipher_ctrl's CTRL_INIT.

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
            // multi-cycle) instead of completing in 1 cycle flat.
            if (sword_ctr_reg == 3'h4 && encdec && keylen && (round_ctr_reg == 4'h1))
              begin
                // AES-256's round 1 key was already seeded whole -- no
                // sbox needed, 1 cycle straight through to CTRL_BLOCK_MAIN
                // (encrypt only reaches this skip case, so no round_ctr
                // decrement to mirror here, unlike the completing branch
                // below).
                sword_ctr_new = sword_ctr_reg + 1'b1;
                sword_ctr_we  = 1'b1;
                core_ctrl_new = CTRL_BLOCK_MAIN;
                core_ctrl_we  = 1'b1;
              end
            else if (!sbox_busy_reg)
              begin
                // Issue: present this sub-cycle's request. For sword_ctr<4
                // (cipher SubBytes/InvSubBytes), update_type=SBOX_UPDATE is
                // safe here -- the eventual commit only depends on
                // new_sboxw, not on old_block, so no premature-write
                // corruption is possible (see the file header comment).
                // For sword_ctr==4 (key schedule), assert ONLY
                // round_key_reverse, NOT round_key_update -- committing
                // here (with new_sboxw not yet valid) would corrupt
                // prev_key0/1_reg/rcon_reg, which the complete cycle's
                // recurrence reads again (see aes_key_mem.sv's header
                // comment).
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
                // prev_key0/1_reg are unchanged since no write happened
                // during the wait -- see the file header comment) so the
                // datapath/key-mem recompute the identical thing, this
                // time actually committing it now that new_sboxw is valid.
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
                        // Matches old decipher_ctrl's round_ctr_dec at SBOX->MAIN.
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

        default:
          begin
          end
      endcase // case (core_ctrl_reg)
    end // aes_core_ctrl

endmodule // aes_core

//======================================================================
// EOF aes_core.sv
//======================================================================
