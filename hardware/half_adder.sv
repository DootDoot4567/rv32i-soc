module half_adder (
    input logic halfAdderIn1,
    input logic halfAdderIn2,

    output logic sum, 
    output logic carryOut
);
    assign sum  = halfAdderIn1 ^ halfAdderIn2;
    assign carryOut = halfAdderIn1 & halfAdderIn2;

endmodule
