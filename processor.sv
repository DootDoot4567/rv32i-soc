module processor #(
    parameter INIT = ""
) (
    input logic clock,
    input logic reset
);
    logic [31:0] pc = 0;

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

    initial 
        begin
            $readmemh("register_init.txt", registerFile);
        end

    logic [31:0] aluOut;
    logic [31:0] writeBackData;

    logic writeBackEnable = 0;
    logic readEnable = 0;

    logic [31:0] nextPcCandidate;
    logic [31:0] writeBackDataCandidate;


    localparam HALT = 3'b000;
    localparam INITIAL = 3'b001;
    localparam FETCH = 3'b010;
    localparam DECODE = 3'b011;
    localparam EXECUTE = 3'b100;
    localparam MEMORY = 3'b101;
    localparam WRITE_BACK = 3'b110;

    logic [3:0] state = HALT; 

    bram_sdp #(
        .WIDTH(32), 
        .DEPTH(128),
        .INIT(INIT)
    ) bram_inst (
        .clockWrite(1'b0),
        .clockRead(clock),
        .writeEnable(1'b0),
        .readEnable(readEnable),
        .addrWrite(7'b0),
        .addrRead(pc[8:2]),
        .dataIn(0),
        .dataOut(dataOut)
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
        .pc,
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
        .Uimm,
        .Iimm,
        .Simm,
        .Bimm,
        .Jimm,
        .funct3,
        .funct7,
        .aluOut,
        .writeBackDataCandidate,
        .nextPcCandidate
    );
   
    always @(posedge clock) 
        begin
            case(state)
                HALT: 
                    begin
                        if (reset) 
                            begin
                                pc <= 12;
                                writeBackEnable <= 0;
                                state <= INITIAL;
                            end
                        else
                            begin
                                state <= HALT;
                            end
                    end
                INITIAL:
                    begin
                        readEnable <= 1;
                        state <= FETCH;
                    end
                FETCH:
                    begin
                        readEnable <= 1;
                        state <= DECODE;
                    end
                DECODE: 
                    begin
                        instr <= dataOut;
                        readEnable <= 0;
                        rs1 <= registerFile[rs1Id];
                        rs2 <= registerFile[rs2Id];
                        state <= EXECUTE;
                    end
                EXECUTE: 
                    begin
                        if (!isSYSTEM) 
                            begin
                                if (!isSYSTEM)
                                    begin
                                        if (pc == 288)
                                            begin
                                                pc <= 0;
                                            end
                                        else
                                            begin
                                                pc <= nextPcCandidate;
                                            end
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
                        writeBackData <= writeBackDataCandidate;

                        writeBackEnable <= (!isBranch) & (!isStore);

                        if(writeBackEnable && rdId != 0) 
                            begin
                                registerFile[rdId] <= writeBackData;
                
                                // `ifdef SIMULATION	 
                                //          $display("x%0d <= %b",rdId,writeBackData);
                                // `endif	 
                            end
                        
                        state <= FETCH;
                    end
            endcase 
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