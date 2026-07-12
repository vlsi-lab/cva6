// Ascon Accelerator IP - Loosely
// Round-constant lookup table for the Ascon permutation.
// Ported from CHIMERA's ascon_round_constants_gen.vhd (same 12 constants,
// same round_number -> constant mapping, translated 1:1 into SystemVerilog).

module ascon_round_constants_gen (
    input  logic [3:0] round_number_i,
    output logic [7:0] round_constant_o
);

  always_comb begin
    unique case (round_number_i)
      4'h0: round_constant_o = 8'hf0;
      4'h1: round_constant_o = 8'he1;
      4'h2: round_constant_o = 8'hd2;
      4'h3: round_constant_o = 8'hc3;
      4'h4: round_constant_o = 8'hb4;
      4'h5: round_constant_o = 8'ha5;
      4'h6: round_constant_o = 8'h96;
      4'h7: round_constant_o = 8'h87;
      4'h8: round_constant_o = 8'h78;
      4'h9: round_constant_o = 8'h69;
      4'ha: round_constant_o = 8'h5a;
      4'hb: round_constant_o = 8'h4b;
      default: round_constant_o = 8'h00;
    endcase
  end

endmodule
