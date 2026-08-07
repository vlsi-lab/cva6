//  v4: one of three interchangeable aes_sbox backends (see aes_sbox.sv's
//  header comment and aes_sbox_pkg.sv). Four independent
//  aes_sbox_bp_byte units (one per byte lane), a registered 32-bit result,
//  and the same one-entry response-buffer handshake aes_sbox_dp_rom.sv
//  uses -- both are 1-cycle-latency backends, so the sequencing is
//  identical; only the substitution itself (Boolean network here, ROM
//  lookup there) differs.
//
//  See aes_sbox_bp_byte.sv for the circuit provenance/attribution
//  (Boyar/Peralta/Calik, Circuit Minimization Work project) -- this file
//  is original (just wiring/handshake), but is not Secworks-derived either
//  since it has no ROM/table content at all.

`default_nettype none

module aes_sbox_bp (
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
  // Four byte-wide Boolean units, one per lane -- no state, no memory.
  //----------------------------------------------------------------
  wire [7 : 0] byte0_out, byte1_out, byte2_out, byte3_out;

  aes_sbox_bp_byte byte0(.inv(inv), .data_i(sboxw[31 : 24]), .data_o(byte0_out));
  aes_sbox_bp_byte byte1(.inv(inv), .data_i(sboxw[23 : 16]), .data_o(byte1_out));
  aes_sbox_bp_byte byte2(.inv(inv), .data_i(sboxw[15 : 08]), .data_o(byte2_out));
  aes_sbox_bp_byte byte3(.inv(inv), .data_i(sboxw[07 : 00]), .data_o(byte3_out));

  //----------------------------------------------------------------
  // Registered 32-bit result, latched only while actually accepting a
  // request -- while a response is held (rsp_valid && !rsp_ready), inv/
  // sboxw may already be changing for the next request, so the register
  // must not keep re-sampling the (now combinational, always-live) byte
  // units' outputs.
  //----------------------------------------------------------------
  wire accept = req_valid && req_ready;

  reg [31 : 0] result_reg;

  always @ (posedge clk)
    if (accept)
      result_reg <= {byte0_out, byte1_out, byte2_out, byte3_out};

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
  assign new_sboxw = result_reg;

endmodule // aes_sbox_bp

//======================================================================
// EOF aes_sbox_bp.sv
//======================================================================
