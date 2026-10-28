module wallace_reduce_four_two #(
    parameter int W = 65
) (
    input  logic [W-1:0] row0, row1, row2, row3,
    output logic [W-1:0] sum_out,
    output logic [W-1:0] carry_out
);
    logic [W-1:0] carryOut_vec;  // inter-column chain, NOT a ripple path
    logic [W-1:0] carryIn_vec;
    logic [W-1:0] carry_raw;     // weight-c carry from each compressor, pre-shift

    // column c's carryIn = column c-1's carryOut; column 0 has no carry-in
    assign carryIn_vec = {carryOut_vec[W-2:0], 1'b0};

    four_two_compressor comp [W-1:0] (
        .compressorIn1(row0),
        .compressorIn2(row1),
        .compressorIn3(row2),
        .compressorIn4(row3),
        .carryIn      (carryIn_vec),
        .sum          (sum_out),
        .carry        (carry_raw),
        .carryOut     (carryOut_vec)
    );

    // carry_raw is weight c -> shift up one position for the carry row
    assign carry_out = {carry_raw[W-2:0], 1'b0};

endmodule