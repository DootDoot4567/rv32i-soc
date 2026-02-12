module decoder(
    input logic [31:0] instr,

    output logic isALUreg,
    output logic isALUimm,
    output logic isBranch,
    output logic isJALR,
    output logic isJAL,
    output logic isAUIPC,
    output logic isLUI,
    output logic isLoad,
    output logic isStore,
    output logic isSYSTEM,

    output logic [4:0] rs1Id,
    output logic [4:0] rs2Id,
    output logic [4:0] rdId,

    output logic [2:0] funct3,
    output logic [6:0] funct7,
);
    logic [31:0] instr;

    assign isALUreg = (instr[6:0] == 7'b0110011);
    assign isALUimm = (instr[6:0] == 7'b0010011);
    assign isBranch = (instr[6:0] == 7'b1100011);
    assign isJALR   = (instr[6:0] == 7'b1100111);
    assign isJAL    = (instr[6:0] == 7'b1101111);
    assign isAUIPC  = (instr[6:0] == 7'b0010111);
    assign isLUI    = (instr[6:0] == 7'b0110111);
    assign isLoad   = (instr[6:0] == 7'b0000011);
    assign isStore  = (instr[6:0] == 7'b0100011);
    assign isSYSTEM = (instr[6:0] == 7'b1110011);

    assign rs1Id  instr[19:15];
    assign rs2Id = instr[24:20];
    assign rdId  = instr[11:7];

    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];

    assign Uimm = { instr[31], instr[30:12], 12'b0 };
    assign Iimm = {{21{instr[31]}}, instr[30:20]};
    assign Simm = {{21{instr[31]}}, instr[30:25], instr[11:7]};
    assign Bimm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    assign Jimm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

endmodule