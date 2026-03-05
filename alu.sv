module alu(
    input logic [31:0] rs1,
    input logic [31:0] rs2,
    
    input logic [31:0] instr,

    input logic isALUreg,
    input logic isALUimm,
    input logic isBranch,
    input logic isJALR,
    input logic isJAL,
    input logic isAUIPC,
    input logic isLUI,
    input logic isLoad,
    input logic isStore,
    input logic isSYSTEM,

    input logic [31:0] Uimm,
    input logic [31:0] Iimm,
    input logic [31:0] Simm,
    input logic [31:0] Bimm,
    input logic [31:0] Jimm,

    input logic [2:0] funct3,
    input logic [6:0] funct7,

    output logic [31:0] pcJALR,
    output logic [31:0] aluOut,
    output logic isEQ,
    output logic isLTU,
    output logic isLT
);
    //Create a shifter function to flip all 32 bits
    function [31:0] flip32(input [31:0] x);
        //Use if simulator supports array slicing
        //flip32 = x[0 +: 32] = [::-1];

        //Otherwise:
        flip32 = {x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7], 
		    x[8], x[9], x[10], x[11], x[12], x[13], x[14], x[15], 
		    x[16], x[17], x[18], x[19], x[20], x[21], x[22], x[23],
		    x[24], x[25], x[26], x[27], x[28], x[29], x[30], x[31]};
    endfunction
    
    logic [31:0] aluIn1;
    logic [31:0] aluIn2;

    logic [32:0] aluMinus;
    logic [31:0] aluPlus;

    logic [31:0] shifterIn;
    logic [31:0] shifter;
    logic [31:0] leftShift;

    //Drive both inputs for the ALU and ALU operations
    assign aluIn1 = rs1;
    assign aluIn2 = (isALUreg || isBranch) ? rs2 : Iimm;

    assign aluMinus = {1'b1, ~aluIn2} + {1'b0, aluIn1} + 33'b1;
    assign aluPlus = aluIn1 + aluIn2;

    assign isEQ = (aluMinus == 0);
    assign isLTU = aluMinus[32];
    assign isLT = (aluIn1[31] ^ aluIn2[31]) ? aluIn1[31] : aluMinus[32];

    assign shifterIn = (funct3 == 3'b001) ? flip32(aluIn1) : aluIn1;
    assign shifter = $signed({(instr[30] & aluIn1[31]), shifterIn}) >>> aluIn2[4:0];

    assign leftShift = flip32(shifter);

    assign pcJALR = {aluPlus[31:1], 1'b0};
 
    //Define combinatorial operatations in ALU
    always @(*)
        begin
            case(funct3)
                3'b000: aluOut = (funct7[5] & instr[5]) ? aluMinus[31:0] : aluPlus;
                3'b001: aluOut = leftShift;
                3'b010: aluOut = {31'b0, isLT};
	            3'b011: aluOut = {31'b0, isLTU};
	            3'b100: aluOut = (aluIn1 ^ aluIn2);
	            3'b101: aluOut = shifter;
	            3'b110: aluOut = (aluIn1 | aluIn2);
	            3'b111: aluOut = (aluIn1 & aluIn2);
            endcase
        end

endmodule