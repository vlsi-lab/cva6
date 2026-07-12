// Ascon Accelerator IP - Loosely
// Ascon permutation datapath: 320-bit state register + round counter.
// Ported 1:1 from CHIMERA's ascon_datapath.vhd (same state machine, same
// round-input muxing, same "reg_data xor (din masked by permutation_computed)"
// trick that lets the state register double as both the "load new input" and
// "keep iterating" path) into SystemVerilog, using clk_i/rst_ni naming.

module ascon_dp
  import ascon_pkg::*;
(
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic                    start_i,
    input  logic [STATE_WIDTH-1:0]  din_i,
    input  logic [3:0]              start_cnt_i,
    output logic                    ready_o,
    output logic [STATE_WIDTH-1:0]  dout_o
);

  logic [STATE_WIDTH-1:0] reg_data_q, round_in, round_out;
  logic [STATE_WIDTH-1:0] permutation_computed_ext;
  logic [3:0] counter_nr_rounds_q;
  logic [7:0] round_constant;
  logic compute_permutation_q;
  logic permutation_computed_q;

  ascon_lane_t x0_i, x1_i, x2_i, x3_i, x4_i;
  ascon_lane_t x0_o, x1_o, x2_o, x3_o, x4_o;

  ascon_round i_ascon_round (
      .x0_i(x0_i),
      .x1_i(x1_i),
      .x2_i(x2_i),
      .x3_i(x3_i),
      .x4_i(x4_i),
      .c_i (round_constant),
      .x0_o(x0_o),
      .x1_o(x1_o),
      .x2_o(x2_o),
      .x3_o(x3_o),
      .x4_o(x4_o)
  );

  ascon_round_constants_gen i_ascon_round_constants_gen (
      .round_number_i(counter_nr_rounds_q),
      .round_constant_o(round_constant)
  );

  // state register + round counter
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      reg_data_q             <= '0;
      counter_nr_rounds_q     <= '0;
      permutation_computed_q  <= 1'b1;
      compute_permutation_q   <= 1'b0;
    end else begin
      if (start_i) begin
        reg_data_q            <= '0;
        counter_nr_rounds_q    <= start_cnt_i;
        compute_permutation_q  <= 1'b1;
        permutation_computed_q <= 1'b1;
      end else begin
        if (compute_permutation_q && permutation_computed_q) begin
          // first round of the permutation
          counter_nr_rounds_q    <= counter_nr_rounds_q + 4'd1;
          permutation_computed_q <= 1'b0;
          reg_data_q             <= round_out;
        end else begin
          if (counter_nr_rounds_q < 4'd11 && !permutation_computed_q) begin
            counter_nr_rounds_q <= counter_nr_rounds_q + 4'd1;
            reg_data_q          <= round_out;
          end
          if (counter_nr_rounds_q == 4'd11) begin
            permutation_computed_q <= 1'b1;
            compute_permutation_q  <= 1'b0;
            counter_nr_rounds_q    <= '0;
            reg_data_q             <= round_out;
          end
        end
      end
    end
  end

  // rate part: while idle (permutation_computed_q=1) the round datapath is
  // continuously fed the new input; while iterating, it's fed back the
  // current state register.
  assign permutation_computed_ext = {STATE_WIDTH{permutation_computed_q}};
  assign round_in = reg_data_q ^ (din_i & permutation_computed_ext);

  assign x4_i = round_in[STATE_WIDTH-1 -: LANE_WIDTH];
  assign x3_i = round_in[STATE_WIDTH-1-LANE_WIDTH -: LANE_WIDTH];
  assign x2_i = round_in[STATE_WIDTH-1-2*LANE_WIDTH -: LANE_WIDTH];
  assign x1_i = round_in[STATE_WIDTH-1-3*LANE_WIDTH -: LANE_WIDTH];
  assign x0_i = round_in[LANE_WIDTH-1:0];

  assign round_out = {x4_o, x3_o, x2_o, x1_o, x0_o};

  assign dout_o  = reg_data_q;
  assign ready_o = permutation_computed_q;

endmodule
