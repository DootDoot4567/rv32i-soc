module alu(
    input logic [31:0] rs1,
    input logic [31:0] rs2,
    
    input logic [31:0] pc,
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

    output logic [31:0] aluOut,
    output logic [31:0] writeBackDataCandidate,
    output logic [31:0] nextPcCandidate
);
    //Create a shifter function to flip all 32 bits
    function [31:0] flip32(input [31:0] x);
        flip32 = x[0 +: 32] = [::-1]; //Reverse all 32 bits 
    endfunction

    //Declare and initialize both inputs for the ALU
    logic [31:0] aluIn1 = rs1;
    logic [31:0] aluIn2 = isALUreg | isBranch ? rs2 : Iimm;

    logic [32:0] aluMinus = {1'b1, ~aluIn2} + {1'b0, aluIn1} + 33'b1;
    logic [31:0] aluPlus = aluIn1 + aluIn2;

    logic isEquality = (aluMinus == 0);
    logic isLessThanUnsigned = aluMinus[32];
    logic isLessthanSigned = (aluIn1 ^ aluIn2) ? aluIn1[31] : aluMinus[32];

    logic [31:0] shifterIn = (funct3 == 3'b001) ? flip32(aluIn1) : aluIn1;
    logic [31:0] shifter = $signed({(instr[30] & aluIn1[31]), shifterIn}) >>> aluIn2[4:0];

    logic [31:0] leftShift = flip32(shifter);

    logic [31:0] pcPlusImm = pc + ( instr[3] ? Jimm[31:0] :
				                    instr[4] ? Uimm[31:0] :
				                    Bimm[31:0] );
        
    logic [31:0] pcPlus4 = pc + 4;

    //Define combinatorial operatations in ALU
    always_comb 
        begin
            //Alu logic 
            case(funct3)
                3'b000: aluOut = (funct7[5] & instr[5]) ? aluMinus[31:0] : aluPlus;
                3'b001: aluOut = leftShift;
                3'b010: aluOut = {31'b0, isLessthanSigned};
	            3'b011: aluOut = {31'b0, isLessThanUnsigned};
	            3'b100: aluOut = (aluIn1 ^ aluIn2);
	            3'b101: aluOut = shifter;
	            3'b110: aluOut = (aluIn1 | aluIn2);
	            3'b111: aluOut = (aluIn1 & aluIn2);
            endcase

            //Branch decision logic 
            case(funct3)
                3'b000: takeBranch = isEquality;
                3'b001: takeBranch = !isEquality;
                3'b100: takeBranch = isLessthanSigned;
                3'b101: takeBranch = !isLessthanSigned;
                3'b110: takeBranch = isLessThanUnsigned;
                3'b111: takeBranch = !isLessThanUnsigned;

	            default: takeBranch = 1'b0;
            endcase

            //Computed values for the writeback and the next program counter
            writeBackDataCandidate = (isJAL || isJALR) ? (pcPlus4) :
			                            (isLUI) ? Uimm :
                                        (isAUIPC) ? pcPlusImm :
			                             aluOut;

            nextPcCandidate = ((isBranch && takeBranch) || isJAL) ? 
                                pcPlusImm  : isJALR ? 
                                    {aluPlus[31:1],1'b0} : pcPlus4;
        end
endmodule