//  v4: one of three interchangeable aes_sbox backends (see aes_sbox.sv's
//  header comment and aes_sbox_pkg.sv). This one trades area for
//  throughput versus aes_sbox_serial_rom.sv: two physical copies of the
//  same 512x8 ROM (0x000-0x0ff forward, 0x100-0x1ff inverse -- see
//  rtl/aes_sbox_512.mem), each with two read ports, giving four
//  independent byte lookups (one 32-bit word) every cycle. Reference: the
//  table values are unmodified from secworks/aes
//  (see https://github.com/secworks/aesaes); the dual-copy/dual-port
//  organization and the req/rsp handshake are new for v4.

//======================================================================
//
// aes_sbox_dp_rom.sv
// -------------------
// AES S-box / inverse S-box, replicated dual-port: two 512x8 ROM copies,
// two read ports per copy, one-cycle registered latency, one 32-bit word
// per cycle when not stalled.
//
//
// Author: Joachim Strombergson (original table values)
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

// See aes_sbox_serial_rom.sv's header comment for why this defaults the
// way it does.
`ifndef AES_SBOX_MEM_PATH
  `define AES_SBOX_MEM_PATH "../rtl/aes_sbox_512.mem"
`endif

module aes_sbox_dp_rom (
                         input  wire        clk,
                         input  wire        reset_n,

                         input  wire        req_valid,
                         output wire        req_ready,
                         input  wire        inv,
                         input  wire [31:0] sboxw,

                         output wire        rsp_valid,
                         input  wire        rsp_ready,
                         output wire [31:0] new_sboxw
                        );

  //----------------------------------------------------------------
  // Two logical 512x8 ROM copies, same contents, two read ports each --
  // copy 0 serves the top two bytes, copy 1 the bottom two.
  //----------------------------------------------------------------
  reg [7 : 0] rom_0 [0 : 511];
  reg [7 : 0] rom_1 [0 : 511];

  initial
    begin
      $readmemh(`AES_SBOX_MEM_PATH, rom_0);
      $readmemh(`AES_SBOX_MEM_PATH, rom_1);
    end

  wire [8 : 0] addr_0a = {inv, sboxw[31 : 24]};
  wire [8 : 0] addr_0b = {inv, sboxw[23 : 16]};
  wire [8 : 0] addr_1a = {inv, sboxw[15 : 08]};
  wire [8 : 0] addr_1b = {inv, sboxw[07 : 00]};

  reg [7 : 0] data_0a, data_0b, data_1a, data_1b;

  //----------------------------------------------------------------
  // One-cycle registered reads, gated on actually accepting a request --
  // while a response is held (rsp_valid && !rsp_ready), no new address is
  // ever latched in, so the held result can't drift.
  //----------------------------------------------------------------
  wire accept = req_valid && req_ready;

  always @ (posedge clk)
    if (accept)
      begin
        data_0a <= rom_0[addr_0a];
        data_0b <= rom_0[addr_0b];
        data_1a <= rom_1[addr_1a];
        data_1b <= rom_1[addr_1b];
      end

  //----------------------------------------------------------------
  // rsp_valid tracking: set the cycle after an accepted request, cleared
  // once consumed -- a one-entry response buffer.
  //----------------------------------------------------------------
  reg rsp_valid_reg;

  always @ (posedge clk or negedge reset_n)
    begin : reg_update
      if (!reset_n)
        rsp_valid_reg <= 1'b0;
      else if (accept)
        rsp_valid_reg <= 1'b1;
      else if (rsp_ready)
        rsp_valid_reg <= 1'b0;
    end

  //----------------------------------------------------------------
  // Concurrent assignments for ports.
  //----------------------------------------------------------------
  assign req_ready = !rsp_valid_reg || rsp_ready;
  assign rsp_valid = rsp_valid_reg;
  assign new_sboxw = {data_0a, data_0b, data_1a, data_1b};

endmodule // aes_sbox_dp_rom

//======================================================================
// EOF aes_sbox_dp_rom.sv
//======================================================================
