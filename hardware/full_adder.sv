module full_adder (
    input logic fullAdderIn1,
    input logic fullAdderIn2,
    input logic carryIn,

    output logic sum,
    output logic carryOut
);
    logic halfAdderOut1;
    logic halfAdderCarryOut1;
    logic halfAdderCarryOut2;

    half_adder half_adder_inst1 (
        .halfAdderIn1(fullAdderIn1),
        .halfAdderIn2(fullAdderIn2),
        .sum(halfAdderOut1),
        .carryOut(halfAdderCarryOut1)
    );

    half_adder half_adder_inst2 (
        .halfAdderIn1(halfAdderOut1),
        .halfAdderIn2(carryIn),
        .sum(sum),
        .carryOut(halfAdderCarryOut2)
    );

    assign carryOut = halfAdderCarryOut1 | halfAdderCarryOut2;

endmodule
