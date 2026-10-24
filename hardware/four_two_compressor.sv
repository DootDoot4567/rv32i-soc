module four_two_compressor (
    input logic compressorIn1,
    input logic compressorIn2,
    input logic compressorIn3,
    input logic compressorIn4,

    input logic carryIn,

    output logic sum,
    output logic carry,
    output logic carryOut
);
    logic sum1;

    full_adder full_adder_inst1 (
        .fullAdderIn1(compressorIn1),
        .fullAdderIn2(compressorIn2),
        .carryIn(compressorIn3),
        .sum(sum1),
        .carryOut(carryOut)
    );

    full_adder full_adder_inst2 (
        .fullAdderIn1(sum1),
        .fullAdderIn2(compressorIn4),
        .carryIn(carryIn),
        .sum(sum),
        .carryOut(carry)
    );

endmodule