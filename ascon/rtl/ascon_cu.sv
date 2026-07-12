// Ascon Accelerator IP - Loosely
// Control unit for the Ascon permutation: a 3-state FSM (wait_start /
// do_permutation / permutation_finished) that counts rounds from a
// round-count-dependent start offset up to 11 and pulses done for one cycle.
// Behaviourally identical to CHIMERA's hw/ascon/ascon_cu.sv, rewritten with
// modern SystemVerilog constructs (typedef enum, single always_comb with
// defaults) instead of the legacy `reg`/magic-number style of the original.

module ascon_cu (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  logic       start_i,
    input  logic       ready_dp_i,
    input  logic [1:0] number_permutations_i,
    output logic [3:0] start_cnt_o,
    output logic       start_dp_o,
    output logic       status_o,
    output logic       done_o
);

  typedef enum logic [1:0] {
    WAIT_START,
    DO_PERMUTATION,
    PERMUTATION_FINISHED
  } state_e;

  // start offsets into the 12-entry round-constant sequence: requesting N
  // rounds starts the shared counter at (12-N) so it still finishes at 11.
  localparam logic [3:0] SixPerm = 4'b0110;  // 6 rounds  -> start at 6
  localparam logic [3:0] EightPerm = 4'b0100;  // 8 rounds  -> start at 4
  localparam logic [3:0] TwelvePerm = 4'b0000;  // 12 rounds -> start at 0

  state_e state_q, state_d;
  logic [3:0] counter_q;
  logic [3:0] start_cnt;

  always_comb begin
    unique case (number_permutations_i)
      2'b01:   start_cnt = SixPerm;
      2'b10:   start_cnt = EightPerm;
      default: start_cnt = TwelvePerm;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= WAIT_START;
      counter_q <= '0;
    end else begin
      state_q <= state_d;
      if (state_d == DO_PERMUTATION) begin
        counter_q <= counter_q + 4'd1;
        if (start_i && ready_dp_i) begin
          counter_q <= start_cnt;
        end
      end
    end
  end

  always_comb begin
    done_o       = 1'b0;
    status_o     = 1'b0;
    start_dp_o   = 1'b0;
    start_cnt_o  = '0;
    state_d      = state_q;

    unique case (state_q)
      WAIT_START: begin
        if (start_i && ready_dp_i) begin
          start_dp_o  = 1'b1;
          start_cnt_o = start_cnt;
          state_d     = DO_PERMUTATION;
        end
      end
      DO_PERMUTATION: begin
        if (counter_q == 4'd11) begin
          state_d = PERMUTATION_FINISHED;
        end
      end
      PERMUTATION_FINISHED: begin
        status_o = 1'b1;
        done_o   = 1'b1;
        state_d  = WAIT_START;
      end
      default: state_d = WAIT_START;
    endcase
  end

endmodule
