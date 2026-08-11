/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Auth: Alessandra Dolmeta, Valeria Piscopo                                       //
// @ EDGE group, at VLSI-LAB, Politecnico di Torino                                //
// Date: August 2026                                                               //
// Desc: Unified AES/Keccak accelerator core, area-optimized sibling of            //
//       keccak_aes_k_top.sv (../v2/keccak_aes_k_top.sv) -- NO internal working    //
//       state register at all.                                                   //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

//  keccak_aes_k_top.sv (the design this is derived from) already unified AES and
//  Keccak onto ONE FSM and ONE 1600-bit register (`state_reg`) -- but that
//  register is still a *second* copy of the same 1600/128 bits the AXI wrapper's
//  register file (KECCAK_DATA0-24 / BLOCK0-1) also holds: software writes the
//  register file, the core loads/reads its own state_reg once, computes, and the
//  wrapper copies the result back into the register file once more at the end.
//  Real Vivado synthesis of kecc_aes_k_axi_top (see tests/result.md's "Area,
//  loosely-coupled AXI accelerator" section) shows that duplication costs real
//  area: the register file + AXI bridge together are roughly as large as the
//  compute core itself.
//
//  This module removes state_reg entirely, following the exact pattern the
//  sibling keccak-only project (cva6-keccak-loosely/keccak_ip/rtl/keccak_dp.sv)
//  already uses for Keccak alone: the round-transform logic (keccak_round.sv,
//  aes_encipher_datapath.sv, aes_decipher_block.sv -- all pure combinational,
//  unmodified, reused as-is from ../v2/) reads its input LIVE from the AXI
//  wrapper's register file every cycle and writes its output back into the SAME
//  register file location on the same cycle, gated by a write-enable pulse. The
//  register file's own flip-flops -- not a second copy in this module -- ARE the
//  working storage, for both Keccak's full 1600-bit state (all 25 KECCAK_DATA
//  words, exactly like the keccak-only precedent) and now also AES's 128-bit
//  block (BLOCK0-1, unified with the wrapper's kecc_aes_k_axi_unified.hjson,
//  which -- unlike the non-unified map -- makes BLOCK0-1 hardware-writable at
//  32-bit-word granularity, matching AES's word-serial SBOX substitution phase).
//
//  One direct consequence: there is no separate `result`/RESULT0-1 output at
//  all. AES is naturally an in-place transform (128 bits in, 128 bits out) --
//  once STATUS.RESULT_VALID/`result_valid` is asserted, aes_block_o (mirrored
//  live into BLOCK0-1 by the wrapper) already holds the final ciphertext/
//  plaintext; there is nothing left to copy anywhere.
//
//  AES's key SCHEDULE (aes_key_mem's internal key_mem[] RAM, up to 15 round
//  keys) is NOT part of this unification: it is a value *derived* from the
//  256-bit KEY register by the expansion algorithm, not a copy of anything the
//  AXI interface itself exposes (the register map only ever exposed the raw
//  key, never the expanded schedule) -- so it necessarily stays private,
//  internal storage here exactly as it already was in keccak_aes_k_top.sv.
//
//  Port list, external handshake (CTRL/STATUS semantics), and the AES/Keccak
//  FSM sequencing itself are otherwise identical to keccak_aes_k_top.sv -- only
//  where round results get COMMITTED changes (external live register-file
//  storage instead of an internal register), not the algorithm, the round
//  count, or the cycle-by-cycle timing of when a round completes.

`default_nettype none

import pkg_keccak::k_state;

module keccak_aes_k_top_unified (
                input  wire            clk,
                input  wire            reset_n,
                input  wire            zeroize,   //  scrub KECCAK_DATA/BLOCK (via keccak_state_o/aes_block_o
                                                   //  forced to 0, we forced to 1 for one cycle) + the AES key
                                                   //  schedule. Bounded at 1 cycle, takes priority over any
                                                   //  in-flight operation (ready stays low throughout)

                input  wire            sel,       //  0 = keccak, 1 = aes
                input  wire            encdec,    //  aes only: 1=encrypt, 0=decrypt
                input  wire            keylen,    //  aes only: 0=128-bit, 1=256-bit

                input  wire            init,      //  aes only: start key schedule
                input  wire            next,      //  aes: run block: keccak: start permute
                output wire            ready,     //  1 = idle / operation complete

                input  wire [255 : 0]  key,           //  aes only

                //  AES's round-by-round working register AND result -- live,
                //  read every cycle from the AXI wrapper's BLOCK0-1 registers
                //  (aes_block_i), committed back into the SAME registers every
                //  INIT/SBOX/MAIN/FINAL sub-step (aes_block_o + the four
                //  per-word write-enables, one per 32-bit BLOCK sub-field --
                //  see aes_encipher_datapath.sv's block_w0_we..block_w3_we,
                //  the SBOX phase substitutes one word at a time).
                input  wire [127 : 0]  aes_block_i,
                output wire [127 : 0]  aes_block_o,
                output wire            aes_block_w0_we,   //  aes_block_o[127:96]
                output wire            aes_block_w1_we,   //  aes_block_o[095:64]
                output wire            aes_block_w2_we,   //  aes_block_o[063:32]
                output wire            aes_block_w3_we,   //  aes_block_o[031:00]
                output wire            result_valid,  //  aes only: aes_block_i/o holds the result while this is 1

                //  Keccak's full 1600-bit permutation state -- live, read every
                //  cycle from the AXI wrapper's KECCAK_DATA0-24 registers
                //  (keccak_state_i), committed back into the SAME registers
                //  every one of the 24 rounds (keccak_state_o +
                //  keccak_state_we, a single enable for all 25 words since a
                //  Keccak round always updates the whole state at once).
                //  Word i = bits [64*i +: 64], matching the vendored core's
                //  own w=5*y+x lane packing.
                input  wire [1599 : 0] keccak_state_i,
                output wire [1599 : 0] keccak_state_o,
                output wire            keccak_state_we,
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
  // Registers -- control/sequencing state only. No 1600-bit or 128-bit
  // working-data register anywhere in this module (see file header).
  //----------------------------------------------------------------
  reg [2 : 0] core_ctrl_reg;
  reg [2 : 0] core_ctrl_new;
  reg         core_ctrl_we;

  // Shared between AES's key_mem[]/block round-index (0..14) and Keccak's
  // round index (0..23) -- the two never run at the same time (`sel`).
  reg [4 : 0] round_ctr_reg;
  reg [4 : 0] round_ctr_new;
  reg         round_ctr_we;

  reg [1 : 0] sword_ctr_reg;   // AES-only: SBOX phase's word-serial sub-counter
  reg [1 : 0] sword_ctr_new;
  reg         sword_ctr_we;

  reg         ready_reg;
  reg         ready_new;
  reg         ready_we;

  reg         result_valid_reg;
  reg         result_valid_new;
  reg         result_valid_we;

  // Genuine one-cycle registered pulse (mirrors ready_reg/result_valid_reg's
  // timing exactly -- NOT combinationally re-derived from round_ctr_reg,
  // which reads 23 a cycle *before* the 24th/final round actually commits,
  // one cycle too early for a "done" signal to fire on).
  reg         keccak_done_reg;
  reg         keccak_done_new;
  reg         keccak_done_we;


  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  reg  [2 : 0] update_type;
  reg  [4 : 0] num_rounds;

  // state_keccak_we_i: this cycle's Keccak round should commit (internal
  // name kept close to keccak_aes_k_top.sv's state_keccak_we for review-
  // ability; zeroize is ORed in below to produce the actual keccak_state_we
  // output port).
  reg          state_keccak_we_i;

  wire [127 : 0] old_block = aes_block_i;   // live from the register file, not a local copy

  wire [127 : 0] round_key;
  reg            round_key_update;

  wire [31 : 0]  keymem_sboxw;
  wire [31 : 0]  enc_sboxw;
  wire [31 : 0]  dec_sboxw;
  wire [31 : 0]  new_sboxw;
  reg  [31 : 0]  muxed_sboxw;
  reg            sbox_inv;

  wire [127 : 0] enc_block_new;
  wire           enc_w0_we, enc_w1_we, enc_w2_we, enc_w3_we;
  wire [127 : 0] dec_block_new;
  wire           dec_w0_we, dec_w1_we, dec_w2_we, dec_w3_we;

  wire [127 : 0] muxed_block_new = encdec ? enc_block_new : dec_block_new;
  wire           muxed_w0_we_i   = encdec ? enc_w0_we     : dec_w0_we;
  wire           muxed_w1_we_i   = encdec ? enc_w1_we     : dec_w1_we;
  wire           muxed_w2_we_i   = encdec ? enc_w2_we     : dec_w2_we;
  wire           muxed_w3_we_i   = encdec ? enc_w3_we     : dec_w3_we;

  wire [7 : 0]   keccak_round_const;  // 8 bits: see keccak_round_constants_gen.sv
  k_state        keccak_state_i_typed;
  k_state        keccak_round_out;


  //----------------------------------------------------------------
  // keccak_state_i (flat 1600 bits, live from the register file) <-> its
  // k_state view for keccak_round, and keccak_round_out -> keccak_state_o
  // (flat, committed back into the register file every round): lane
  // L = 5y+x occupies bits [64L+63 : 64L], matching the vendored core's
  // (and keccak_dp.sv's original) Dout-flattening convention exactly.
  //----------------------------------------------------------------
  genvar gy, gx;
  generate
    for (gy = 0; gy < 5; gy = gy + 1) begin : g_lane_y
      for (gx = 0; gx < 5; gx = gx + 1) begin : g_lane_x
        assign keccak_state_i_typed[gy][gx]        = keccak_state_i[320*gy + 64*gx +: 64];
        assign keccak_state_o[320*gy + 64*gx +: 64] = zeroize ? 64'h0 : keccak_round_out[gy][gx];
      end
    end
  endgenerate


  //----------------------------------------------------------------
  // Instantiations -- same pure-combinational AES/Keccak datapath modules
  // keccak_aes_k_top.sv uses, unmodified, driven by the same FSM below.
  // `block`/`old_block` now both read aes_block_i live (no local copy);
  // `Round_in` now reads keccak_state_i_typed live (no local copy).
  //----------------------------------------------------------------
  aes_encipher_datapath enc_dp(
                               .update_type(update_type),
                               .sword_ctr(sword_ctr_reg),

                               .block(aes_block_i),
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
                            .sword_ctr(sword_ctr_reg),

                            .block(aes_block_i),
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
                     .round_key_update(round_key_update),
                     .round_key(round_key),

                     .sboxw(keymem_sboxw),
                     .new_sboxw(new_sboxw)
                    );

  aes_sbox sbox_inst(.inv(sbox_inv), .sboxw(muxed_sboxw), .new_sboxw(new_sboxw));

  keccak_round_constants_gen rc_gen(
                                    .round_number(round_ctr_reg),
                                    .round_constant_signal_out(keccak_round_const)
                                   );

  keccak_round kround(
                      .Round_in(keccak_state_i_typed),
                      .Round_constant_signal(keccak_round_const),
                      .Round_out(keccak_round_out)
                     );


  //----------------------------------------------------------------
  // Concurrent connectivity for ports etc.
  //----------------------------------------------------------------
  assign ready           = ready_reg;
  assign result_valid    = result_valid_reg;
  assign keccak_done     = keccak_done_reg;

  assign aes_block_o     = zeroize ? 128'h0 : muxed_block_new;
  assign aes_block_w0_we = zeroize | muxed_w0_we_i;
  assign aes_block_w1_we = zeroize | muxed_w1_we_i;
  assign aes_block_w2_we = zeroize | muxed_w2_we_i;
  assign aes_block_w3_we = zeroize | muxed_w3_we_i;

  assign keccak_state_we = zeroize | state_keccak_we_i;


  //----------------------------------------------------------------
  // reg_update -- control/sequencing registers only (see file header: no
  // working-data register lives in this always block anymore).
  //----------------------------------------------------------------
  always @ (posedge clk or negedge reset_n)
    begin: reg_update
      if (!reset_n)
        begin
          round_ctr_reg     <= 5'h0;
          sword_ctr_reg     <= 2'h0;
          result_valid_reg  <= 1'b0;
          ready_reg         <= 1'b1;
          keccak_done_reg   <= 1'b0;
          core_ctrl_reg     <= CTRL_IDLE;
        end
      else if (zeroize)
        begin
          // core_ctrl_reg still moves to CTRL_ZEROIZE via the normal
          // core_ctrl_we/new path below (driven by core_ctrl's own
          // top-priority `if (zeroize)` check) -- the working-data scrub
          // itself is the keccak_state_o/aes_block_o/*_we combinational
          // forcing above, not anything in this always block.
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
        end
      else
        begin
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
        end
    end // reg_update


  //----------------------------------------------------------------
  // sbox_mux
  //
  // Controls which of the key memory, encipher, or decipher datapath
  // gets access to the one shared (forward + inverse) sbox this cycle.
  // (Unused/don't-care during Keccak phases -- nothing reads new_sboxw
  // then, since update_type stays NO_UPDATE.)
  //----------------------------------------------------------------
  always @*
    begin : sbox_mux
      if (core_ctrl_reg == CTRL_KEY_GEN)
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
  // decipherment, and the Keccak-f[1600] permutation. Identical
  // sequencing to keccak_aes_k_top.sv's core_ctrl -- state_load_din is
  // gone (keccak_state_i is live every cycle, nothing to explicitly load:
  // the register file already holds whatever software last wrote, exactly
  // like the keccak-only precedent's state_i), and state_keccak_we is
  // renamed state_keccak_we_i (now a combinational output instead of an
  // internal register's write-enable).
  //----------------------------------------------------------------
  always @*
    begin : core_ctrl
      core_ctrl_new      = CTRL_IDLE;
      core_ctrl_we       = 1'b0;
      round_ctr_new      = 5'h0;
      round_ctr_we       = 1'b0;
      sword_ctr_new      = 2'h0;
      sword_ctr_we       = 1'b0;
      ready_new          = 1'b0;
      ready_we           = 1'b0;
      result_valid_new   = 1'b0;
      result_valid_we    = 1'b0;
      round_key_update   = 1'b0;
      update_type        = NO_UPDATE;
      state_keccak_we_i  = 1'b0;
      keccak_done_new    = 1'b0;
      keccak_done_we     = 1'b1;  // clear every cycle by default -- 1-cycle pulse

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
                round_ctr_new = 5'h0;
                round_ctr_we  = 1'b1;
                ready_new     = 1'b0;
                ready_we      = 1'b1;
                core_ctrl_new = CTRL_KEY_GEN;
                core_ctrl_we  = 1'b1;
              end
            else if (next && (sel == SEL_AES))
              begin
                // Encrypt walks key_mem[] up from 0; decrypt walks it down
                // from num_rounds -- same asymmetry the non-unified core had.
                round_ctr_new    = encdec ? 5'h0 : num_rounds;
                round_ctr_we     = 1'b1;
                ready_new        = 1'b0;
                ready_we         = 1'b1;
                result_valid_new = 1'b0;
                result_valid_we  = 1'b1;
                core_ctrl_new    = CTRL_BLOCK_INIT;
                core_ctrl_we     = 1'b1;
              end
            else if (next && (sel == SEL_KECCAK))
              begin
                // No state_load_din step: keccak_state_i already reflects
                // whatever software last wrote into KECCAK_DATA -- round 0
                // reads it live on the very next cycle.
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
            round_key_update = 1'b1;
            round_ctr_new    = round_ctr_reg + 1'b1;
            round_ctr_we     = 1'b1;

            if (round_ctr_reg == num_rounds)
              begin
                ready_new     = 1'b1;
                ready_we      = 1'b1;
                core_ctrl_new = CTRL_IDLE;
                core_ctrl_we  = 1'b1;
              end
          end

        CTRL_BLOCK_INIT:
          begin
            update_type   = INIT_UPDATE;
            sword_ctr_new = 2'h0;
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
            update_type   = SBOX_UPDATE;
            sword_ctr_new = sword_ctr_reg + 1'b1;
            sword_ctr_we  = 1'b1;

            if (sword_ctr_reg == 2'h3)
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

        CTRL_BLOCK_MAIN:
          begin
            sword_ctr_new = 2'h0;
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
            state_keccak_we_i = 1'b1;
            round_ctr_new      = round_ctr_reg + 1'b1;
            round_ctr_we       = 1'b1;

            if (round_ctr_reg == 5'd23)
              begin
                // This cycle's state_keccak_we_i commits the 24th/final
                // round (RC[23]) into the register file on the upcoming
                // edge -- ready_reg and keccak_done_reg land on that exact
                // same edge, so both become visible in lockstep with the
                // finished result, same timing keccak_aes_k_top.sv had.
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

endmodule // keccak_aes_k_top_unified

//======================================================================
// EOF keccak_aes_k_top_unified.sv
//======================================================================
