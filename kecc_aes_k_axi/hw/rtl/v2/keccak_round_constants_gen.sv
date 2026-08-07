//////////////////////////////////////////////////////////////////////////////////////////
// Authors:      Alessandra Dolmeta - alessandra.dolmeta@polito.it                      //
//               Valeria Piscopo    - valeria.piscopo@polito.it                         //
// Design Name:  keccak_round_constants_gen                                             //
// Language:     SystemVerilog                                                          //
//                                                                                      //
// Derived from cva6-keccak-loosely/keccak_ip's keccak_round_constants_gen.sv (Josh     //
// Moles, MIT license, http://keccak.noekeon.org/ VHDL translation) -- optimized here to //
// output 8 bits instead of the original 64: across all 24 official Keccak-f[1600]      //
// round constants, only bit positions {0,1,3,7,15,31,63} are ever nonzero (a direct     //
// consequence of the LFSR-based generation rule, RC[round][2^j-1] = rc(j+7*round) for   //
// j=0..6, everything else always 0) -- bit 2 is unused padding, kept only to round the  //
// encoding out to a full byte. See keccak_round.sv's iota stage for the corresponding   //
// bit-position mapping; each table entry below is the original 64-bit constant's bits   //
// {63,31,15,7,3,2,1,0} repacked into one byte, verified against all 24 NIST/Keccak      //
// reference values.                                                                    //
//                                                                                      //
//////////////////////////////////////////////////////////////////////////////////////////


module keccak_round_constants_gen(
        input   [4:0]          round_number,
        output  logic [7:0]  round_constant_signal_out);

    always_comb
    begin
        case(round_number)
            5'b00000 : round_constant_signal_out = 8'h01;
            5'b00001 : round_constant_signal_out = 8'h32;
            5'b00010 : round_constant_signal_out = 8'hBA;
            5'b00011 : round_constant_signal_out = 8'hE0;
            5'b00100 : round_constant_signal_out = 8'h3B;
            5'b00101 : round_constant_signal_out = 8'h41;
            5'b00110 : round_constant_signal_out = 8'hF1;
            5'b00111 : round_constant_signal_out = 8'hA9;
            5'b01000 : round_constant_signal_out = 8'h1A;
            5'b01001 : round_constant_signal_out = 8'h18;
            5'b01010 : round_constant_signal_out = 8'h69;
            5'b01011 : round_constant_signal_out = 8'h4A;
            5'b01100 : round_constant_signal_out = 8'h7B;
            5'b01101 : round_constant_signal_out = 8'h9B;
            5'b01110 : round_constant_signal_out = 8'hB9;
            5'b01111 : round_constant_signal_out = 8'hA3;
            5'b10000 : round_constant_signal_out = 8'hA2;
            5'b10001 : round_constant_signal_out = 8'h90;
            5'b10010 : round_constant_signal_out = 8'h2A;
            5'b10011 : round_constant_signal_out = 8'hCA;
            5'b10100 : round_constant_signal_out = 8'hF1;
            5'b10101 : round_constant_signal_out = 8'hB0;
            5'b10110 : round_constant_signal_out = 8'h41;
            5'b10111 : round_constant_signal_out = 8'hE8;
            default : round_constant_signal_out = '0;

        endcase
    end

endmodule
