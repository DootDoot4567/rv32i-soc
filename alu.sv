module alu(
    input logic [31:0] rs1,
    input logic [31:0] rs2,
    input logic [6:0] isALUreg,

    output logic [31:0] aluOut,
);

    logic [31:0] aluIn1 = rs1;
    logic [31:0] aluIn2 = isALUreg ? rs2 : Iimm;

    logic [4:0] shiftAmount = isALUreg ? rs2[4:0] :  instr[24:20];

    always_comb 
        begin
            case
                3'b000: (func7[5] & func5[5]) ? (aluIn1 - aluIn2) : (aluIn1 + aluIn1);
                3'b001: aluIn1 << shiftAmount;
                3'b010: aluOut = ($signed(aluIn1) < $signed(aluIn2));
	            3'b011: aluOut = (aluIn1 < aluIn2);
	            3'b100: aluOut = (aluIn1 ^ aluIn2);
	            3'b101: aluOut = funct7[5]? ($signed(aluIn1) >>> shamt) : (aluIn1 >> shamt);
	            3'b110: aluOut = (aluIn1 | aluIn2);
	            3'b111: aluOut = (aluIn1 & aluIn2);
            endcase
        end

    //Write back
    assign writeBackData = aluOut;
    assign writeBackEn = (state == EXECUTE && (isALUreg || isALUimm));

endmodule