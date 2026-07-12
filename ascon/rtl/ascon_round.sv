// Ascon Accelerator IP - Loosely
// One full Ascon permutation round (constant addition + Sbox + linear layer).
// Ported from CHIMERA's ascon_round.vhd, same equations, translated 1:1 into
// SystemVerilog. Verified to match the NIST-LWC reference C ROUND() macro
// (CHIMERA/sw/applications/original/LWC/ASCON/ascon128v12/include/round.h).

module ascon_round
  import ascon_pkg::*;
(
    input  ascon_lane_t x0_i,
    input  ascon_lane_t x1_i,
    input  ascon_lane_t x2_i,
    input  ascon_lane_t x3_i,
    input  ascon_lane_t x4_i,
    input  logic [7:0]  c_i,       // round constant
    output ascon_lane_t x0_o,
    output ascon_lane_t x1_o,
    output ascon_lane_t x2_o,
    output ascon_lane_t x3_o,
    output ascon_lane_t x4_o
);

  function automatic ascon_lane_t ror(input ascon_lane_t x, input int unsigned n);
    ror = (x >> n) | (x << (LANE_WIDTH - n));
  endfunction

  always_comb begin
    ascon_lane_t x0, x1, x2, x3, x4, xtemp;

    x0 = x0_i;
    x1 = x1_i;
    x2 = x2_i;
    x3 = x3_i;
    x4 = x4_i;

    // addition of round constant
    x2 = x2 ^ ascon_lane_t'(c_i);

    // substitution layer (Keccak-style Sbox)
    x0 = x0 ^ x4;
    x4 = x4 ^ x3;
    x2 = x2 ^ x1;
    xtemp = x0 & ~x4;
    x0 = x0 ^ (x2 & ~x1);
    x2 = x2 ^ (x4 & ~x3);
    x4 = x4 ^ (x1 & ~x0);
    x1 = x1 ^ (x3 & ~x2);
    x3 = x3 ^ xtemp;
    x1 = x1 ^ x0;
    x3 = x3 ^ x2;
    x0 = x0 ^ x4;
    x2 = ~x2;

    // linear diffusion layer
    x0_o = x0 ^ ror(x0, 19) ^ ror(x0, 28);
    x1_o = x1 ^ ror(x1, 61) ^ ror(x1, 39);
    x2_o = x2 ^ ror(x2, 1) ^ ror(x2, 6);
    x3_o = x3 ^ ror(x3, 10) ^ ror(x3, 17);
    x4_o = x4 ^ ror(x4, 7) ^ ror(x4, 41);
  end

endmodule
