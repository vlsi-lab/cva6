///////////////////////////////////////////////////////////////////////
// File: kecc_aes_k_xif_aes_mixcolumns.sv
// Date: 2024-04-02
// Author: Behnam Farnaghinejad <behnam.farnaghinejad@polito.it>
// Ported unchanged from aes-ext/cva6/core/crypto/crypto_aes_mix_columns.sv
// into the kecc_aes_k_xif coprocessor.
//
// Description:
// This file contains two modules: `crypto_aes_mixcolumn_fwd` and
// `crypto_aes_mixcolumn_dec`. These modules implement the MixColumns
// and Inverse MixColumns transformations used in the AES encryption
// algorithm. The `crypto_aes_mixcolumn_enc` module performs the forward
// MixColumns transformation, while the `crypto_aes_mixcolumn_dec` module
// performs the inverse MixColumns transformation.
//
// Forward MixColumns matrix:
// [ 2 3 1 1 ]
// [ 1 2 3 1 ]
// [ 1 1 2 3 ]
// [ 3 1 1 2 ]
//
// Inverse MixColumns matrix:
// [ 14 11 13  9 ]
// [  9 14 11 13 ]
// [ 13  9 14 11 ]
// [ 11 13  9 14 ]
//
///////////////////////////////////////////////////////////////////////


// This module implements the forward MixColumns transformation for AES encryption.
// It performs matrix multiplication on the input column to produce the output column.
module crypto_aes_mixcolumn_enc (

input   logic [31:0] column_in    ,
output  logic [31:0] column_out

);

    // Intermediate variables for byte operations
    logic [ 7:0] b0, _2b0, _3b0 ;
    logic [ 7:0] b1, _2b1, _3b1 ;
    logic [ 7:0] b2, _2b2, _3b2 ;
    logic [ 7:0] b3, _2b3, _3b3 ;

    // Split the input column into four bytes
    assign  b0 = column_in[ 7: 0];
    assign  b1 = column_in[15: 8];
    assign  b2 = column_in[23:16];
    assign  b3 = column_in[31:24];

    // Compute the intermediate values for the forward transformation
        // x2 multiplication
    assign _2b0 = (b0 << 1) ^ ({8{b0[7]}} & 8'h1b);
    assign _2b1 = (b1 << 1) ^ ({8{b1[7]}} & 8'h1b);
    assign _2b2 = (b2 << 1) ^ ({8{b2[7]}} & 8'h1b);
    assign _2b3 = (b3 << 1) ^ ({8{b3[7]}} & 8'h1b);
        // x3 multiplication
    assign _3b0 = _2b0 ^ b0;
    assign _3b1 = _2b1 ^ b1;
    assign _3b2 = _2b2 ^ b2;
    assign _3b3 = _2b3 ^ b3;

    // Compute the output bytes for the forward transformation
    logic [7:0] mix_out_0;
    logic [7:0] mix_out_1;
    logic [7:0] mix_out_2;
    logic [7:0] mix_out_3;

    // Perform matrix multiplication for MixColumns
        // mix_out_0 = 2*b0 + 3*b1 + 1*b2 + 1*b3
        // mix_out_1 = 1*b0 + 2*b1 + 3*b2 + 1*b3
        // mix_out_2 = 1*b0 + 1*b1 + 2*b2 + 3*b3
        // mix_out_3 = 3*b0 + 1*b1 + 1*b2 + 2*b3
    assign mix_out_0 = _2b0 ^ _3b1 ^   b2 ^   b3;
    assign mix_out_1 =   b0 ^ _2b1 ^ _3b2 ^   b3;
    assign mix_out_2 =   b0 ^   b1 ^ _2b2 ^ _3b3;
    assign mix_out_3 = _3b0 ^   b1 ^   b2 ^ _2b3;

    // Combine the output bytes into a single output column
    assign column_out = {mix_out_3, mix_out_2, mix_out_1, mix_out_0};

endmodule

//----------------------------------------------------------------------

// This module implements the inverse MixColumns transformation for AES decryption.
// It performs matrix multiplication on the input column to produce the output column.
module crypto_aes_mixcolumn_dec (

input   logic [31:0] column_in    ,
output  logic [31:0] column_out

);
    // Intermediate variables for byte operations
    logic [ 7:0] b0, _2b0, _4b0, _8b0;
    logic [ 7:0] b1, _2b1, _4b1, _8b1;
    logic [ 7:0] b2, _2b2, _4b2, _8b2;
    logic [ 7:0] b3, _2b3, _4b3, _8b3;

    // Split the input column into four bytes
    assign  b0 = column_in[ 7: 0];
    assign  b1 = column_in[15: 8];
    assign  b2 = column_in[23:16];
    assign  b3 = column_in[31:24];

    // Compute the intermediate values for the inverse transformation
        // x2 multiplication
    assign _2b0 = (b0 << 1) ^ ({8{b0[7]}} & 8'h1b);
    assign _2b1 = (b1 << 1) ^ ({8{b1[7]}} & 8'h1b);
    assign _2b2 = (b2 << 1) ^ ({8{b2[7]}} & 8'h1b);
    assign _2b3 = (b3 << 1) ^ ({8{b3[7]}} & 8'h1b);
        // x4 multiplication
    assign _4b0 = (_2b0 << 1) ^ ({8{_2b0[7]}} & 8'h1b);
    assign _4b1 = (_2b1 << 1) ^ ({8{_2b1[7]}} & 8'h1b);
    assign _4b2 = (_2b2 << 1) ^ ({8{_2b2[7]}} & 8'h1b);
    assign _4b3 = (_2b3 << 1) ^ ({8{_2b3[7]}} & 8'h1b);
        // x8 multiplication
    assign _8b0 = (_4b0 << 1) ^ ({8{_4b0[7]}} & 8'h1b);
    assign _8b1 = (_4b1 << 1) ^ ({8{_4b1[7]}} & 8'h1b);
    assign _8b2 = (_4b2 << 1) ^ ({8{_4b2[7]}} & 8'h1b);
    assign _8b3 = (_4b3 << 1) ^ ({8{_4b3[7]}} & 8'h1b);

    // Compute the intermediate values for the inverse transformation
    logic [7:0] _9b0, _11b0, _13b0, _14b0;
    logic [7:0] _9b1, _11b1, _13b1, _14b1;
    logic [7:0] _9b2, _11b2, _13b2, _14b2;
    logic [7:0] _9b3, _11b3, _13b3, _14b3;

        // x9 multiplication
    assign _9b0 = _8b0 ^ b0;
    assign _9b1 = _8b1 ^ b1;
    assign _9b2 = _8b2 ^ b2;
    assign _9b3 = _8b3 ^ b3;
        // x11 multiplication
    assign _11b0 = _9b0 ^ _2b0;
    assign _11b1 = _9b1 ^ _2b1;
    assign _11b2 = _9b2 ^ _2b2;
    assign _11b3 = _9b3 ^ _2b3;
        // x13 multiplication
    assign _13b0 = _9b0 ^ _4b0;
    assign _13b1 = _9b1 ^ _4b1;
    assign _13b2 = _9b2 ^ _4b2;
    assign _13b3 = _9b3 ^ _4b3;
        // x14 multiplication
    assign _14b0 = _8b0 ^ _4b0 ^ _2b0;
    assign _14b1 = _8b1 ^ _4b1 ^ _2b1;
    assign _14b2 = _8b2 ^ _4b2 ^ _2b2;
    assign _14b3 = _8b3 ^ _4b3 ^ _2b3;

    // Compute the output bytes for the inverse transformation
    logic [7:0] mix_out_0;
    logic [7:0] mix_out_1;
    logic [7:0] mix_out_2;
    logic [7:0] mix_out_3;

    // Perform matrix multiplication for Inverse MixColumns
        // mix_out_0 = 14*b0 + 11*b1 + 13*b2 +  9*b3
        // mix_out_1 =  9*b0 + 14*b1 + 11*b2 + 13*b3
        // mix_out_2 = 13*b0 +  9*b1 + 14*b2 + 11*b3
        // mix_out_3 = 11*b0 + 13*b1 +  9*b2 + 14*b3
    assign mix_out_0 = _14b0 ^ _11b1 ^ _13b2 ^  _9b3;
    assign mix_out_1 =  _9b0 ^ _14b1 ^ _11b2 ^ _13b3;
    assign mix_out_2 = _13b0 ^  _9b1 ^ _14b2 ^ _11b3;
    assign mix_out_3 = _11b0 ^ _13b1 ^  _9b2 ^ _14b3;

    // Combine the output bytes into a single output column
    assign column_out = {mix_out_3, mix_out_2, mix_out_1, mix_out_0};

endmodule
