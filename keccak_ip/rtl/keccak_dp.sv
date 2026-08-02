// The Keccak sponge function, designed by Guido Bertoni, Joan Daemen,
// Michal Peeters and Gilles Van Assche.
//
// keccak_datapath: datapath of keccak core.
// Designed by Mattia Mirigaldi
// mattia.mirigaldi@polito.it
// Keccak-f[1600] permutation datapath.
// No internal state register: state_i is read live from the bus-facing
// register file (the only 1600-bit storage in the design) and state_o/
// state_we_o drive it back every round. Asserting start_i runs 24 rounds
// over whatever state_i currently holds and raises ready_o once finished.

import pkg_keccak::k_state;
import pkg_keccak::KEC_N;
import pkg_keccak::IN_BUF_SIZE;
import pkg_keccak::OUT_BUF_SIZE;

module keccak_dp (
    input clk,
    input rst_n,  // asynchronous, active-low
    input start_i,   // pulse: start a new permutation over state_i
    input k_state state_i,    // current state, live from the register file
    output k_state state_o,   // next state to commit into the register file
    output state_we_o,        // asserted when state_o should be committed this cycle
    output ready_o);   // ’1’ when permutation finished / idle


    //--------------------------------------------------------------------
    //  Internal signals
    //--------------------------------------------------------------------

    k_state               round_out;

    logic        [4:0]            counter_nr_rounds;
    logic        [KEC_N-1:0]      round_constant_signal;
    logic                       compute_permutation;
    logic                       permutation_computed;

    //--------------------------------------------------------------------
    //  Sub-blocks
    //--------------------------------------------------------------------
    keccak_round round_map (
        .Round_in              ( state_i               ),
        .Round_constant_signal ( round_constant_signal ),
        .Round_out             ( round_out             )
    );

    keccak_round_constants_gen round_constants_gen (
        .round_number              ( counter_nr_rounds   ),
        .round_constant_signal_out ( round_constant_signal )
    );

    assign state_o = round_out;

    //--------------------------------------------------------------------
    //  Control FSM
    //--------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // asynchronous clear
            counter_nr_rounds     <= '0;
            permutation_computed  <= 1'b1;
            compute_permutation   <= 1'b0;
        end
         else begin
            if (start_i) begin
                // arm the core over state_i (whatever software last loaded
                // into the register file)
                counter_nr_rounds     <= '0;
                compute_permutation   <= 1'b1;
                permutation_computed  <= 1'b1;
            end
            else begin
                // normal operation
                if (compute_permutation && permutation_computed) begin
                    // start round 0
                    counter_nr_rounds      <= 5'b00001;
                    permutation_computed   <= 1'b0;
                end
                else begin
                    if ((counter_nr_rounds < 24) && !permutation_computed) begin
                        counter_nr_rounds  <= counter_nr_rounds + 1'b1;
                    end
                    if (counter_nr_rounds == 23) begin
                        permutation_computed <= 1'b1;   // done!
                        compute_permutation  <= 1'b0;
                        counter_nr_rounds    <= '0;
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------------
    //  Output flags
    //--------------------------------------------------------------------
    assign ready_o = permutation_computed;

    // Commit a round result exactly on the same two conditions that used
    // to gate the internal reg_data <= round_out non-blocking assignment.
    assign state_we_o = (compute_permutation && permutation_computed) ||
                         ((counter_nr_rounds < 24) && !permutation_computed);

endmodule
