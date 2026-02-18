module processor #(
    parameter INIT = ""
) (
    input logic clock,
    input logic reset
);
    logic [6:0] pc = 0;

    logic [31:0] dataOut;
    logic [31:0] instr;

    logic isALUreg;
    logic isALUimm;
    logic isBranch;
    logic isJALR;    
    logic isJAL;    
    logic isAUIPC;    
    logic isLUI;    
    logic isLoad;    
    logic isStore;    
    logic isSYSTEM;

    logic [4:0] rs1Id;
    logic [4:0] rs2Id;
    logic [4:0] rdId;

    logic [2:0] funct3;
    logic [6:0] funct7;

    logic [31:0] Uimm;
    logic [31:0] Iimm;
    logic [31:0] Simm;
    logic [31:0] Bimm;
    logic [31:0] Jimm;

    logic [31:0] rs1;
    logic [31:0] rs2;

    logic [31:0] registerFile [31:0];

    logic [31:0] aluOut;
    logic [31:0] writeBackData;

    logic writeBackEnable = 0;
    logic readEnable = 0;
    logic takeBranch;

    localparam HALT = 3'b000;
    localparam INITIAL = 3'b001;
    localparam FETCH = 3'b010;
    localparam DECODE = 3'b011;
    localparam EXECUTE = 3'b100;
    localparam MEMORY = 3'b101;
    localparam WRITE_BACK = 3'b110;

    logic [3:0] state; 

    bram_sdp #(
        .WIDTH(32), 
        .DEPTH(128),
        .INIT(INIT)
    ) bram_inst (
        .clockWrite(1'b0),
        .clockRead(clock),
        .writeEnable(1'b0),
        .readEnable(readEnable),
        .addrWrite(7'b0000000),
        .addrRead(pc),
        .dataIn(0),
        .dataOut
    );

    decoder decoder_inst (
        .instr,
        .isALUreg,
        .isALUimm,
        .isBranch,
        .isJALR,
        .isJAL,
        .isAUIPC,
        .isLUI,
        .isLoad,
        .isStore,
        .isSYSTEM,
        .rs1Id,
        .rs2Id,
        .rdId,
        .funct3,
        .funct7,
        .Uimm,
        .Iimm,
        .Simm,
        .Bimm,
        .Jimm
    );

    alu alu_inst (
        .rs1,
        .rs2,
        .instr,
        .funct3,
        .funct7,
        .isALUreg,
        .Iimm,
        .takeBranch,
        .aluOut
    );
   
    always @(posedge clock) 
        begin
            if(reset) 
                begin
                    if (pc == 71)
                        begin
                            pc <= 0;
                        end
                    else
                        begin
                            pc <= pc + 1;
                        end
                    state <= HALT;
                end 
            else
                begin                  
                    readEnable <= 1;

                    if(writeBackEnable && rdId != 0) 
                        begin
                            registerFile[rdId] <= writeBackData;
            
                            `ifdef SIMULATION	 
                                    $display("x%0d <= %b",rdId,writeBackData);
                            `endif	 
                        end

                    case(state)
                        HALT: 
                            begin
                                state <= HALT;

                                if (reset) 
                                    begin
                                        
                                    end
                            end
                        INITIAL:
                            begin
                                instr <= dataOut;
                            end
                        FETCH:
                            begin
                                readEnable <= 1;
                            end
                        DECODE: 
                            begin
                                rs1 <= registerFile[rs1Id];
                                rs2 <= registerFile[rs2Id];
                                state <= EXECUTE;
                            end
                        EXECUTE: 
                            begin
                                if (!isSYSTEM) 
                                    begin
                                        if (pc == 72)
                                            begin
                                                pc <= 0;
                                            end
                                        else
                                            begin
                                                pc <= (isBranch && takeBranch) ?
                                                     pc+Bimm :
                                                isJAL ? pc+Jimm :
                                                isJALR ? rs1+Iimm :
	                                            pc+4;
                                            end
                                    end
                                
                                state <= MEMORY;	          
                            end
                        MEMORY:
                            begin
                                state <= WRITE_BACK;
                            end
                        WRITE_BACK:
                            begin
                                writeBackData = (isJAL || isJALR) ? (pc + 4) :
                                                (isLUI) ? Uimm :
                                                (isAUIPC) ? (pc + Uimm) :
                                                aluOut;

                                writeBackEnable = (
                                    state == EXECUTE && (
                                        isALUreg || 
                                        isALUimm ||
                                        isJAL ||
                                        isJALR ||
                                        isLUI ||
                                        isAUIPC
                                    )
                                );  
                                state <= FETCH;
                            end
                    endcase 
                end
        end

    `ifdef SIMULATION
        always @(posedge clock) 
            begin
                $display("PC=%0d instr=%h", pc, instr);
                $display("Instruction opcode %b", dataOut[6:0]);
                case (1'b1)
                    isALUreg: $display("ALUreg rd=%0d rs1=%0d rs2=%0d funct3=%b", rdId, rs1Id, rs2Id, funct3);
                    isALUimm: $display("ALUimm rd=%0d rs1=%0d imm=%0d funct3=%b", rdId, rs1Id, Iimm, funct3);
                    isLoad:   $display("LOAD");
                    isStore:  $display("STORE");
                    isBranch: $display("BRANCH");
                    isJAL:    $display("JAL");
                    isJALR:   $display("JALR");
                    isLUI:    $display("LUI");
                    isAUIPC:  $display("AUIPC");
                    isSYSTEM: $display("SYSTEM (EBREAK)");
                endcase
            end
    `endif

endmodule