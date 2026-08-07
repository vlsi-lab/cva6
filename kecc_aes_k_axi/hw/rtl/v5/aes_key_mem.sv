//  v3: on-the-fly key expansion -- key_mem[0:14] (1920 bits, the single
//  largest register block in the whole design) is gone. This module now
//  only ever holds the CURRENT round key (prev_key1_reg) plus, for AES-256,
//  the one PREVIOUS round key it needs alongside it (prev_key0_reg) -- 256
//  bits total, doing double duty as both the forward-generation state
//  (encrypt: interleaved with the cipher rounds; decrypt: an up-front
//  forward walk to reach the last round key) and the backward-walk state
//  (decrypt: recovering each earlier round key from the two most recent
//  ones, one round at a time, algebraically -- see below). Sequencing
//  (`round_key_seed`/`round_key_update`/`round_key_reverse`) now comes from
//  aes_core's/keccak_aes_k_top's own unified controller, same as before.
//
//  Forward (unchanged math from the original secworks/aes schedule, just
//  no longer stored into an array): AES-128 uses only prev_key1_reg
//  (w4..w7); AES-256 alternates trw/tw by round parity using both
//  registers (w0..w3 = prev_key0_reg, w4..w7 = prev_key1_reg). Round 0's
//  (and, for AES-256, round 1's) key needs no computation at all -- it IS
//  the raw external key -- so `round_key_seed` just latches key[255:128]
//  (and key[127:0] for AES-256) directly, priming rcon to the value that
//  makes the first REAL round's Rcon come out to 8'h01 (see rcon_logic in
//  the original secworks core, reproduced here as the immediate 8'h01 seed
//  since seeding now covers what used to be two separate primed+advanced
//  cycles in one).
//
//  Backward (new): AES's round-key recurrence is invertible. Given the
//  CURRENT round key (prev_key1_reg) and, for AES-256, the one before it
//  (prev_key0_reg), the PREVIOUS round key can be recovered with the exact
//  same SubBytes/RotWord/Rcon math run in reverse -- see round_key_step's
//  comments below for the derivation. This lets decrypt walk from the last
//  round key down to round 0 one round at a time, without ever having
//  stored the intermediate keys forward.
//
//  Two round-key outputs, not one: `round_key1` (=prev_key1_reg) is what
//  every consumption point but one wants -- the current round's key.
//  The one exception is encrypt's round-0 AddRoundKey for AES-256: the
//  seed pulse latches BOTH raw-key halves at once (round 0 into
//  prev_key0_reg, round 1 into prev_key1_reg, so round 1 needs no
//  computation either), which means immediately after seeding,
//  prev_key1_reg holds round 1's key, not round 0's -- round 0's key is
//  sitting in prev_key0_reg instead. `round_key0` exposes that so the
//  caller's controller (aes_core.sv/keccak_aes_k_top.sv) can mux the right
//  one in for that one cycle; every other cycle it just uses round_key1.

//======================================================================
//
// aes_key_mem.sv
// -------------
// The AES key memory including round key generator.
//
//
// Author: Joachim Strombergson
// Copyright (c) 2013 Secworks Sweden AB
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

module aes_key_mem(
                   input wire            clk,
                   input wire            reset_n,
                   input wire            zeroize,  //  synchronously scrub prev_key0/1_reg/rcon_reg
                                                    //  to 0 (bounded: 1 cycle, same as reset_n)

                   input wire [255 : 0]  key,
                   input wire            keylen,

                   input wire    [3 : 0] round,              //  aes_core's/keccak_aes_k_top's shared
                                                              //  round_ctr_reg -- parity/context only,
                                                              //  no longer a key_mem[] index
                   input wire            round_key_seed,     //  pulse: latch prev_key0/1_reg straight
                                                              //  from `key` (+ prime rcon) -- the one
                                                              //  "free" step common to both directions
                   input wire            round_key_update,   //  pulse: advance one step (see round_key_reverse)
                   input wire            round_key_reverse,  //  0 = forward (encrypt interleave / decrypt's
                                                              //  up-front walk), 1 = backward (decrypt's
                                                              //  per-round walk); only meaningful together
                                                              //  with round_key_update
                   output wire [127 : 0] round_key0,         //  = prev_key0_reg (AES-256's older/lower half of
                                                              //  the current window; needed standalone only for
                                                              //  encrypt's round-0 AddRoundKey -- see below)
                   output wire [127 : 0] round_key1,         //  = prev_key1_reg -- the current round's key
                                                              //  for every other consumption point

                   output wire [31 : 0]  sboxw,
                   input wire  [31 : 0]  new_sboxw
                  );


  //----------------------------------------------------------------
  // Parameters.
  //----------------------------------------------------------------
  localparam AES_128_BIT_KEY = 1'h0;
  localparam AES_256_BIT_KEY = 1'h1;


  //----------------------------------------------------------------
  // Registers.
  //----------------------------------------------------------------
  reg [127 : 0] prev_key0_reg;
  reg [127 : 0] prev_key0_new;
  reg           prev_key0_we;

  reg [127 : 0] prev_key1_reg;
  reg [127 : 0] prev_key1_new;
  reg           prev_key1_we;

  reg [7 : 0] rcon_reg;
  reg [7 : 0] rcon_new;
  reg         rcon_we;


  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  reg [31 : 0] tmp_sboxw;


  //----------------------------------------------------------------
  // Concurrent assignments for ports.
  //----------------------------------------------------------------
  assign round_key0 = prev_key0_reg;
  assign round_key1 = prev_key1_reg;
  assign sboxw      = tmp_sboxw;


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
          rcon_reg      <= 8'h0;
          prev_key0_reg <= 128'h0;
          prev_key1_reg <= 128'h0;
        end
      else if (zeroize)
        begin
          // Same scrub as reset, but synchronous and caller-triggered --
          // whatever round key is currently in flight is as sensitive as
          // the original key.
          rcon_reg      <= 8'h0;
          prev_key0_reg <= 128'h0;
          prev_key1_reg <= 128'h0;
        end
      else
        begin
          if (rcon_we)
            rcon_reg <= rcon_new;

          if (prev_key0_we)
            prev_key0_reg <= prev_key0_new;

          if (prev_key1_we)
            prev_key1_reg <= prev_key1_new;
        end
    end // reg_update


  //----------------------------------------------------------------
  // round_key_step
  //
  // Seeds prev_key0/1_reg from the raw key, or steps the schedule one
  // round forward (generate) or backward (invert), for AES-128 and
  // AES-256.
  //----------------------------------------------------------------
  always @*
    begin: round_key_step
      reg [31 : 0] w0, w1, w2, w3, w4, w5, w6, w7;
      reg [31 : 0] rconw, rotstw, tw, trw;
      reg [31 : 0] k0, k1, k2, k3;
      reg [7 : 0]  rcon_fwd, rcon_bwd;
      reg [31 : 0] bw0, bw1, bw2, bw3;
      reg [31 : 0] brotstw, btrw, btw;

      // Default assignments.
      prev_key0_new = 128'h0;
      prev_key0_we  = 1'b0;
      prev_key1_new = 128'h0;
      prev_key1_we  = 1'b0;
      rcon_new      = 8'h0;
      rcon_we       = 1'b0;
      tmp_sboxw     = 32'h0;

      k0 = 32'h0; k1 = 32'h0; k2 = 32'h0; k3 = 32'h0;
      bw0 = 32'h0; bw1 = 32'h0; bw2 = 32'h0; bw3 = 32'h0;

      // Extract words from the current 1- or 2-round window.
      w0 = prev_key0_reg[127 : 096];
      w1 = prev_key0_reg[095 : 064];
      w2 = prev_key0_reg[063 : 032];
      w3 = prev_key0_reg[031 : 000];

      w4 = prev_key1_reg[127 : 096];
      w5 = prev_key1_reg[095 : 064];
      w6 = prev_key1_reg[063 : 032];
      w7 = prev_key1_reg[031 : 000];

      rconw  = {rcon_reg, 24'h0};
      rotstw = {new_sboxw[23 : 00], new_sboxw[31 : 24]};
      trw    = rotstw ^ rconw;
      tw     = new_sboxw;

      // xtime(rcon_reg) -- the forward step's rcon advance.
      rcon_fwd = {rcon_reg[6 : 0], 1'b0} ^ (8'h1b & {8{rcon_reg[7]}});
      // Inverse of xtime -- see the file header comment: y's LSB tells you
      // which of xtime's two cases produced it.
      rcon_bwd = rcon_reg[0] ? (((rcon_reg ^ 8'h1b) >> 1) | 8'h80) : (rcon_reg >> 1);

      // v4: tmp_sboxw (what gets sent to the now possibly-multi-cycle
      // shared sbox) is computed here UNCONDITIONALLY -- i.e. independent
      // of round_key_update -- from prev_key0/1_reg alone. This lets
      // aes_core.sv issue an sbox request (sampling tmp_sboxw at accept)
      // on a cycle where it does NOT also assert round_key_update, so
      // prev_key0/1_reg/rcon_reg are never written before the sbox's
      // response is actually valid. If tmp_sboxw were only computed
      // inside the round_key_update-gated branches below (as it used to
      // be), asserting round_key_update just to present it would ALSO
      // commit a premature write (using whatever new_sboxw happens to be
      // before the request completes); since the forward/backward
      // recurrences below read prev_key0/1_reg again on the very cycle
      // they commit, that premature write would corrupt the inputs their
      // own (correct, later) commit depends on.
      if (!round_key_reverse)
        tmp_sboxw = w7;                       // forward: same for both keylens
      else if (keylen == AES_256_BIT_KEY)
        tmp_sboxw = w3;                       // backward, AES-256: prev_key0_reg's word3
      else
        tmp_sboxw = w7 ^ w6;                  // backward, AES-128: bw3, computed early

      if (round_key_seed)
        begin
          // Round 0's (AES-128) or rounds 0+1's (AES-256) key IS the raw
          // key -- no computation needed, just latch it. rcon is primed
          // straight to the value the original secworks core reached after
          // its first real advance (8'h8d -> xtime -> 8'h01), since this
          // one pulse now covers what used to be two separate key_mem[]
          // writes (round 0 and, for AES-256, round 1) each of which
          // could advance rcon on its own.
          case (keylen)
            AES_128_BIT_KEY:
              begin
                prev_key1_new = key[255 : 128];
                prev_key1_we  = 1'b1;
              end

            default: // AES_256_BIT_KEY
              begin
                prev_key0_new = key[255 : 128];
                prev_key0_we  = 1'b1;
                prev_key1_new = key[127 : 0];
                prev_key1_we  = 1'b1;
              end
          endcase // case (keylen)

          rcon_new = 8'h01;
          rcon_we  = 1'b1;
        end

      else if (round_key_update && !round_key_reverse)
        begin
          // Forward: one more round key, from the current window --
          // unchanged math from the original secworks/aes schedule.
          // (tmp_sboxw already presented above, unconditionally.)

          case (keylen)
            AES_128_BIT_KEY:
              begin
                k0 = w4 ^ trw;
                k1 = w5 ^ w4 ^ trw;
                k2 = w6 ^ w5 ^ w4 ^ trw;
                k3 = w7 ^ w6 ^ w5 ^ w4 ^ trw;

                prev_key1_new = {k0, k1, k2, k3};
                prev_key1_we  = 1'b1;
                rcon_new      = rcon_fwd;
                rcon_we       = 1'b1;
              end

            default: // AES_256_BIT_KEY
              begin
                if (round[0] == 1'b0)
                  begin
                    k0 = w0 ^ trw;
                    k1 = w1 ^ w0 ^ trw;
                    k2 = w2 ^ w1 ^ w0 ^ trw;
                    k3 = w3 ^ w2 ^ w1 ^ w0 ^ trw;
                  end
                else
                  begin
                    k0 = w0 ^ tw;
                    k1 = w1 ^ w0 ^ tw;
                    k2 = w2 ^ w1 ^ w0 ^ tw;
                    k3 = w3 ^ w2 ^ w1 ^ w0 ^ tw;
                    rcon_new = rcon_fwd;
                    rcon_we  = 1'b1;
                  end

                prev_key1_new = {k0, k1, k2, k3};
                prev_key1_we  = 1'b1;
                prev_key0_new = prev_key1_reg;
                prev_key0_we  = 1'b1;
              end
          endcase // case (keylen)
        end

      else if (round_key_update && round_key_reverse)
        begin
          // Backward: recover the PREVIOUS round key from the current
          // window -- inverting the exact same recurrence above.
          //
          // AES-128 (single-register recurrence: k0=w4^trw, k1=w5^w4^trw,
          // k2=w6^w5^w4^trw, k3=w7^w6^w5^w4^trw, all against prev_key1_reg
          // alone): given the current key (ck0..ck3 = prev_key1_reg),
          //   pk3 = ck3^ck2, pk2 = ck2^ck1, pk1 = ck1^ck0,
          //   pk0 = ck0 ^ RotWord(SubWord(pk3)) ^ rconw
          // Rcon decrements every round here (it also advances every
          // round going forward), using rcon_bwd for THIS step's trw and
          // storing that same decremented value back for the next step.
          //
          // AES-256 (2-round-window recurrence: k=f(prev_key0=K[r-2],
          // prev_key1=K[r-1])): given the current window (prev_key0=K[r-1],
          // prev_key1=K[r]), the SAME shape recovers K[r-2]:
          //   bw3=w7^w6, bw2=w6^w5, bw1=w5^w4 (w4..w7 = prev_key1_reg = K[r])
          //   bw0 = w4 ^ nonlin(prev_key0_reg's word3 = K[r-1]'s word3)
          // then shift the window down: prev_key1<=prev_key0 (=K[r-1],
          // already known -- no computation needed for it), prev_key0<=the
          // newly-recovered K[r-2]. Rcon only advanced forward on ODD
          // rounds (see the original schedule's rcon_next), so backward
          // only decrements when undoing an ODD round.
          case (keylen)
            AES_128_BIT_KEY:
              begin
                bw3 = w7 ^ w6;
                bw2 = w6 ^ w5;
                bw1 = w5 ^ w4;
                // (tmp_sboxw already presented above, unconditionally.)
                btrw      = {new_sboxw[23 : 00], new_sboxw[31 : 24]} ^ {rcon_bwd, 24'h0};
                bw0       = w4 ^ btrw;

                prev_key1_new = {bw0, bw1, bw2, bw3};
                prev_key1_we  = 1'b1;
                rcon_new      = rcon_bwd;
                rcon_we       = 1'b1;
              end

            default: // AES_256_BIT_KEY
              begin
                bw3 = w7 ^ w6;
                bw2 = w6 ^ w5;
                bw1 = w5 ^ w4;
                // (tmp_sboxw already presented above, unconditionally.)

                if (round[0] == 1'b0)
                  begin
                    // Undoing an EVEN round: its forward step read
                    // rcon_reg as-is (no advance) -- so we do too.
                    btrw = {new_sboxw[23 : 00], new_sboxw[31 : 24]} ^ {rcon_reg, 24'h0};
                    bw0  = w4 ^ btrw;
                  end
                else
                  begin
                    // Undoing an ODD round: its own math never touched
                    // rcon, but its forward step advanced it afterward --
                    // undo that advance here so the next (even) backward
                    // step sees the right value.
                    btw      = new_sboxw;
                    bw0      = w4 ^ btw;
                    rcon_new = rcon_bwd;
                    rcon_we  = 1'b1;
                  end

                prev_key1_new = prev_key0_reg;   // K[r-1], already known
                prev_key1_we  = 1'b1;
                prev_key0_new = {bw0, bw1, bw2, bw3};
                prev_key0_we  = 1'b1;
              end
          endcase // case (keylen)
        end
    end // round_key_step

endmodule // aes_key_mem

//======================================================================
// EOF aes_key_mem.sv
//======================================================================
