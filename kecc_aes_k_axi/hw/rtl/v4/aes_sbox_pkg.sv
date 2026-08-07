// v4: implementation-selection constants for the configurable aes_sbox
// (rtl/aes_sbox.sv). Plain localparam int unsigned rather than an enum, so
// the selector stays a simple integer both in RTL parameter lists and in
// the -G command-line overrides testbench/Makefile passes to Verilator.

`default_nettype none

package aes_sbox_pkg;

  localparam int unsigned AES_SBOX_IMPL_SERIAL_ROM = 0;  // 512x8 ROM, 1 addr/cycle, 4-cycle word latency
  localparam int unsigned AES_SBOX_IMPL_DP_ROM     = 1;  // 2x 512x8 ROM, 2 ports each, 1-cycle word latency
  localparam int unsigned AES_SBOX_IMPL_BP         = 2;  // Boyar-Peralta Boolean network, 1-cycle word latency

endpackage

`default_nettype wire
