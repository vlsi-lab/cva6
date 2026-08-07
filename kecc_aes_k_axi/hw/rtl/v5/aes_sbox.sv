//  v4: configurable AES S-box wrapper. Previously this file held both the
//  forward and inverse tables directly (see git history) behind a purely
//  combinational port; that content has moved into three interchangeable,
//  elaboration-time-selected backends -- exactly one is ever synthesized:
//
//    SBOX_IMPL == AES_SBOX_IMPL_SERIAL_ROM (default) -> aes_sbox_serial_rom.sv
//      one logical 512x8 ROM, one byte/cycle, 4-cycle word latency.
//    SBOX_IMPL == AES_SBOX_IMPL_DP_ROM               -> aes_sbox_dp_rom.sv
//      two 512x8 ROM copies, two ports each, 1-cycle word latency.
//    SBOX_IMPL == AES_SBOX_IMPL_BP                   -> aes_sbox_bp.sv
//      Boyar-Peralta Boolean network, no memory, 1-cycle word latency.
//
//  `SBOX_IMPL` is an elaboration-time parameter (see aes_sbox_pkg.sv), not
//  a runtime signal -- picking it with a runtime mux would keep all three
//  architectures in the netlist, defeating the point of comparing them.
//  `aes_core.sv`/`keccak_aes_k_top.sv` forward their own `SBOX_IMPL`
//  parameter straight into their `aes_sbox` instance, so
//  testbench/Makefile's SBOX_IMPL variable (passed to Verilator as a -G
//  override on the *top* module) reaches this parameter.
//
//  The old combinational `sboxw -> new_sboxw` port is gone -- none of the
//  three backends can honestly claim 0-cycle latency (a ROM read takes at
//  least a cycle; the Boolean network is combinational internally but this
//  wrapper still registers its result for a uniform interface, see
//  aes_sbox_bp.sv). The new port is a synchronous request/response
//  handshake instead; see any of the three backend files for the exact
//  handshake contract they all share, and aes_core.sv's/
//  keccak_aes_k_top.sv's "S-box transaction sequencer" comment for how the
//  AES control FSMs now wait on it.

`default_nettype none

import aes_sbox_pkg::AES_SBOX_IMPL_SERIAL_ROM;
import aes_sbox_pkg::AES_SBOX_IMPL_DP_ROM;
import aes_sbox_pkg::AES_SBOX_IMPL_BP;

module aes_sbox #(
                   parameter int unsigned SBOX_IMPL = AES_SBOX_IMPL_SERIAL_ROM
                  )(
                    input  wire        clk,
                    input  wire        reset_n,

                    input  wire        req_valid,
                    output wire        req_ready,
                    input  wire        inv,        //  0 = forward S-box, 1 = inverse S-box
                    input  wire [31:0] sboxw,

                    output wire        rsp_valid,
                    input  wire        rsp_ready,
                    output wire [31:0] new_sboxw
                   );

  generate
    if (SBOX_IMPL == AES_SBOX_IMPL_SERIAL_ROM)
      begin : gen_serial_rom
        aes_sbox_serial_rom impl (.*);
      end
    else if (SBOX_IMPL == AES_SBOX_IMPL_DP_ROM)
      begin : gen_dp_rom
        aes_sbox_dp_rom impl (.*);
      end
    else if (SBOX_IMPL == AES_SBOX_IMPL_BP)
      begin : gen_bp
        aes_sbox_bp impl (.*);
      end
    else
      begin : gen_invalid
        initial
          $fatal(1, "aes_sbox: unsupported SBOX_IMPL=%0d", SBOX_IMPL);
      end
  endgenerate

endmodule // aes_sbox

//======================================================================
// EOF aes_sbox.sv
//======================================================================
