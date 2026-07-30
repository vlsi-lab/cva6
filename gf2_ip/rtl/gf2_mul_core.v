/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Auth: Alessandra Dolmeta, Valeria Piscopo                                       //
// @ EDGE group, at VLSI-LAB, Politecnico di Torino                                //
// Date: July 2026                                                                 //
// Desc: GF(2^ACC_WIDTH)-by-GF(2^128) bit-serial multiply-reduce core              //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

//  === Hardware version of fields.c's software windowed multiply (bf128_mul()/
//      bf384_mul_128_inplace()) -- but here the whole 128-bit `rhs` is
//      processed 1 bit/cycle instead of 4 (no need for a lookup-table
//      trade-off in hardware: a plain shift+conditional-XOR per cycle is
//      already the fastest and smallest option, since there's no per-call
//      software-loop overhead to amortize a table build against). Same
//      shift-and-reduce recurrence as the software algorithm, replayed in
//      hardware:
//
//          result = 0
//          tmp    = lhs
//          for idx in 0..127:
//              if rhs[idx]: result ^= tmp
//              tmp = (tmp << 1); if tmp's old top bit was set: tmp ^= MODULUS
//
//      ACC_WIDTH is 128 (for bf128_mul()) or 384 (for bf384_mul_128_inplace())
//      -- `rhs` is always 128 bits either way (FAEST never multiplies by
//      anything wider), so ONE core design serves both, instantiated twice
//      in rtl/gf2_mmio.v with a different ACC_WIDTH/MODULUS each time.
//      MODULUS is the field's fixed reduction polynomial (bf128_modulus =
//      0x87, bf384_modulus = 0x100D in software/faest-opt/common/src/
//      fields.c) -- both are small (<=13 bits), so a plain XOR of the
//      MODULUS constant into the low bits after each left-shift is exact,
//      no wider reduction ever needed (same argument fields.c's own header
//      comments make for why bf128_reduce4[]/bf384_reduce4[] never need
//      further reduction either).
//
//      Latency: 128 cycles (1 initial + 127 loop steps) regardless of
//      ACC_WIDTH, plus a couple of cycles of pulse/poll overhead -- see
//      rtl/gf2_mmio.v.

module gf2_mul_core #(
    parameter integer           ACC_WIDTH = 128,
    parameter [383:0]           MODULUS   = 384'h87
)(
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     next,           //  pulse: start a multiply
    output reg                      ready,          //  idle, can accept `next`
    input  wire [ACC_WIDTH-1:0]     lhs,            //  multiplicand
    input  wire [127:0]             rhs,            //  multiplier (always 128b)
    output reg  [ACC_WIDTH-1:0]     result,
    output reg                      result_valid
);

    localparam [ACC_WIDTH-1:0] MOD_W = MODULUS[ACC_WIDTH-1:0];

    reg  [ACC_WIDTH-1:0]    tmp;
    reg  [127:0]            rhs_r;
    reg  [6:0]              bit_cnt;    //  0..127, matches rhs_r's index width
    reg                     busy;

    wire [ACC_WIDTH-1:0]    shifted   = { tmp[ACC_WIDTH-2:0], 1'b0 };
    wire [ACC_WIDTH-1:0]    next_tmp  = tmp[ACC_WIDTH-1] ? (shifted ^ MOD_W) : shifted;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ready        <= 1'b1;
            busy         <= 1'b0;
            result_valid <= 1'b0;
            bit_cnt      <= 7'd0;
            tmp          <= {ACC_WIDTH{1'b0}};
            rhs_r        <= 128'd0;
            result       <= {ACC_WIDTH{1'b0}};
        end else begin
            result_valid <= 1'b0;

            if (next && ready) begin
                //  idx == 0 step: no shift/reduce yet, just the bit-0 select
                result   <= rhs[0] ? lhs : {ACC_WIDTH{1'b0}};
                tmp      <= lhs;
                rhs_r    <= rhs;
                bit_cnt  <= 7'd1;
                busy     <= 1'b1;
                ready    <= 1'b0;

            end else if (busy) begin
                //  idx == bit_cnt step: shift+reduce tmp, then conditionally
                //  fold the NEW tmp into result if this bit of rhs is set --
                //  matches fields.c's bit-serial loop order exactly (shift
                //  happens before the conditional add, every iteration)
                tmp <= next_tmp;
                if (rhs_r[bit_cnt]) result <= result ^ next_tmp;

                if (bit_cnt == 7'd127) begin
                    busy         <= 1'b0;
                    ready        <= 1'b1;
                    result_valid <= 1'b1;
                end else begin
                    bit_cnt <= bit_cnt + 7'd1;
                end
            end
        end
    end

endmodule
