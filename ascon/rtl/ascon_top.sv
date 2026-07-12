// Ascon Accelerator IP - Loosely
// Standalone Ascon permutation core: datapath + control unit + round-count
// decode. Ported 1:1 from CHIMERA's hw/ascon/ascon.vhd (same instance
// wiring, same round-count decode policy: 6 or 8 selects the shorter
// permutation, anything else (including the literal 12) defaults to the
// full 12-round permutation), but with the number-of-rounds input narrowed
// from a 32-bit bus down to the 4 bits that are actually decoded.

module ascon_top
  import ascon_pkg::*;
(
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic                   start_i,
    input  logic [STATE_WIDTH-1:0] din_i,
    input  logic [3:0]             number_rounds_i,
    output logic [STATE_WIDTH-1:0] dout_o,
    output logic                   done_o
);

  logic start_dp, ready_dp;
  logic [3:0] start_cnt;
  logic [1:0] number_permutations;

  always_comb begin
    if (number_rounds_i == 4'b0110) begin
      number_permutations = 2'b01;  // six rounds
    end else if (number_rounds_i == 4'b1000) begin
      number_permutations = 2'b10;  // eight rounds
    end else begin
      number_permutations = 2'b11;  // twelve rounds (default)
    end
  end

  ascon_dp i_ascon_dp (
      .clk_i      (clk_i),
      .rst_ni     (rst_ni),
      .start_i    (start_dp),
      .din_i      (din_i),
      .start_cnt_i(start_cnt),
      .ready_o    (ready_dp),
      .dout_o     (dout_o)
  );

  ascon_cu i_ascon_cu (
      .clk_i                (clk_i),
      .rst_ni               (rst_ni),
      .start_i              (start_i),
      .ready_dp_i           (ready_dp),
      .number_permutations_i(number_permutations),
      .start_cnt_o          (start_cnt),
      .start_dp_o           (start_dp),
      .status_o             (),
      .done_o               (done_o)
  );

endmodule
