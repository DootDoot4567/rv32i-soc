module alu_tb;
    // ALU inputs
    logic [31:0] rs1, rs2, pc;
    logic [31:0] Uimm, Iimm, Simm, Bimm, Jimm;
    logic [31:0] instr;
    logic isALUreg, isALUimm, isBranch, isJALR, isJAL, isAUIPC, isLUI, isLoad, isStore, isSYSTEM;
    logic [2:0] funct3;
    logic [6:0] funct7;

    // ALU outputs
    logic [31:0] aluOut, writeBackDataCandidate, nextPcCandidate;

    // Instantiate your ALU
    alu alu_inst (
        .rs1(rs1),
        .rs2(rs2),
        .pc(pc),
        .instr(instr),
        .isALUreg(isALUreg),
        .isALUimm(isALUimm),
        .isBranch(isBranch),
        .isJALR(isJALR),
        .isJAL(isJAL),
        .isAUIPC(isAUIPC),
        .isLUI(isLUI),
        .isLoad(isLoad),
        .isStore(isStore),
        .isSYSTEM(isSYSTEM),
        .Uimm(Uimm),
        .Iimm(Iimm),
        .Simm(Simm),
        .Bimm(Bimm),
        .Jimm(Jimm),
        .funct3(funct3),
        .funct7(funct7),
        .aluOut(aluOut),
        .writeBackDataCandidate(writeBackDataCandidate),
        .nextPcCandidate(nextPcCandidate)
    );

    initial begin
        // zero everything
        pc = 0;
        instr = 0;
        Uimm = 0;
        Iimm = 0;
        Simm = 0;
        Bimm = 0;
        Jimm = 0;
        isALUimm = 0;
        isBranch = 0;
        isJALR   = 0;
        isJAL    = 0;
        isAUIPC  = 0;
        isLUI    = 0;
        isLoad   = 0;
        isStore  = 0;
        isSYSTEM = 0;

        // Test ADD (R-type)
        rs1 = 32'd10;
        rs2 = 32'd20;
        funct3 = 3'b000;      // ADD/SUB
        funct7 = 7'b0000000;  // ADD
        isALUreg = 1;
        #1 $display("ADD result: %d (expected 30)", aluOut);

        // Test SLTI (I-type)
        rs1 = 32'd10;
        Iimm = 32'd15;
        funct3 = 3'b010;      // SLTI
        isALUreg = 0;
        isALUimm = 1;
        #1 $display("SLTI result: %d (expected 1)", aluOut);

        // Test SUB (R-type)
        rs1 = 32'd50;
        rs2 = 32'd20;
        funct3 = 3'b000;
        funct7 = 7'b0100000;  // SUB
        instr = 32'd32;       // sets instr[5] = 1 to trigger SUB in your ALU
        isALUreg = 1;
        isALUimm = 0;
        #1 $display("SUB result: %d (expected 30)", aluOut);

        // SLTI test: 03212193 -> slti x3, x2, 50
        rs1    = 32'd50;       // value in x2
        Iimm   = 32'd50;       // immediate
        funct3 = 3'b010;       // SLTI
        funct7 = 7'b0000000;   // not used for SLTI
        isALUreg = 0;          // I-type
        isALUimm = 1;          // indicate ALU-IMM
        isBranch = 0;
        isJALR   = 0;
        isJAL    = 0;
        isAUIPC  = 0;
        isLUI    = 0;
        isLoad   = 0;
        isStore  = 0;
        isSYSTEM = 0;

        #1 $display("SLTI result: %d (expected %d)", aluOut, (rs1 < Iimm) ? 1 : 0);

        $finish;
    end
endmodule