module processor #(
    parameter INIT = ""
) (
    input logic clock,
    input logic reset
);
    logic [31:0] pc = 0;

    //BRAM inputs and outputs being declared as logic

    // logic clockWrite = 0;
    // logic clockRead = 0;
    logic writeEnable = 0;
    logic readEnable = 0;
    logic [6:0] addrRead = 0;
    // logic [6:0] addrWrite = 0;
    logic [31:0] dataOut;
    logic [31:0] dataIn;

    logic [31:0] instr;

    //Boolean flags used by the decoder, processor, and alu
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

    //Indexes for input registers and ra register
    logic [4:0] rs1Id;
    logic [4:0] rs2Id;
    logic [4:0] rdId;

    //Optional opcode fields for instruction
    logic [2:0] funct3;
    logic [6:0] funct7;

    logic [31:0] Uimm;
    logic [31:0] Iimm;
    logic [31:0] Simm;
    logic [31:0] Bimm;
    logic [31:0] Jimm;

    logic [31:0] rs1;
    logic [31:0] rs2;

    logic [31:0] registerFile [0:31];

    initial 
        begin
            $readmemh("register_init.txt", registerFile);
        end

    logic [31:0] aluOut;
    logic [31:0] writeBackData;
    logic writeBackEnable = 0;

    logic [31:0] nextPcCandidate;
    logic [31:0] writeBackDataCandidate;

    logic [31:0] memAddr;

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
        .DEPTH(73),
        .INIT(INIT)
    ) bram_inst (
        .clockWrite(clock),
        .clockRead(clock),
        .writeEnable,
        .readEnable,
        .addrWrite(7'b0),
        .addrRead(addrRead),
        .dataIn,
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

    // assign memAddr = rs1 + (isLoad ? Iimm : Simm);

    // logic [7:0] byteData = memAddr[1:0] == 0 ? dataOut[7:0] :
    //                    memAddr[1:0] == 1 ? dataOut[15:8] :
    //                    memAddr[1:0] == 2 ? dataOut[23:16] :
    //                                         dataOut[31:24];

    // logic [31:0] loadData = {{24{byteData[7]}}, byteData};
    // logic [31:0] storeWord = dataOut;

    // always @(*)
    //     begin
    //         if (funct3 == 3'b000)
    //             begin
    //                 case(memAddr[1:0])
    //                     0: storeWord[7:0]   = rs2[7:0];
    //                     1: storeWord[15:8]  = rs2[7:0];
    //                     2: storeWord[23:16] = rs2[7:0];
    //                     3: storeWord[31:24] = rs2[7:0];
    //                 endcase
    //             end
    //     end

    always @(posedge clock) 
        begin
            case(state)
                HALT: 
                    begin
                        if (reset) 
                            begin
                                pc <= 0;
                                state <= INITIAL;
                            end
                    end
                INITIAL:
                    begin

                        //Set up signals for fetch state 

                        readEnable <= 1;
                        //we use the second bit because we increment by 4 for the pc. the 2 bit corresponds to the first line in our .mem file
                        addrRead <= pc[8:2];
                        writeBackEnable <= 0;

                        state <= FETCH;
                    end
                FETCH:
                    begin
                        $display("FETCH");

                        //Schedule readEnable to go down instant of next clock cycle
                        readEnable <= 0;

                        addrRead <= nextPcCandidate[8:2];

                        state <= DECODE;
                    end
                DECODE: 
                    begin
                        $display("DECODE");

                        //calculate branch and jump targets here
                        instr <= dataOut; 
                        //instr <= 32'h123450b7;

                        rs1 <= registerFile[rs1Id];
                        rs2 <= registerFile[rs2Id];

                        state <= EXECUTE;
                    end
                EXECUTE: 
                    begin
                        $display("EXEC");
                        //if its branch or jump then update pc 

                        //if load or a store, then read or write enable goes up so that its ready for mem state

                        if (!isSYSTEM)
                            begin
                                if (pc === 288)
                                    begin
                                        pc <= 0;
                                    end
                                else
                                    begin
                                        pc <= nextPcCandidate;
                                    end
                            end

                        writeEnable <= 1;
                        
                        state <= MEMORY;	          
                    end
                MEMORY:
                    begin
                        $display("MEM");
                        //schedule so that read and write enable to go down
                        //writes to mem

                        if(isLoad) 
                            begin
                                
                            end

                        writeBackData <= writeBackDataCandidate;

                        writeBackEnable <= (!isBranch && !isStore && !isLoad);

                        readEnable <= 0;
                        writeEnable <= 0;

                        state <= WRITE_BACK;
                    end
                WRITE_BACK:
                    begin
                        $display("WB");
                        //writes to register file

                        if(writeBackEnable && rdId != 0) 
                            begin
                                registerFile[rdId] <= writeBackData;

                                `ifdef SIMULATION	 
                                          $display("x%0d <= %b",rdId,writeBackData);
                                `endif
                            end

                        writeBackEnable <= 0;
                        readEnable <= 1;
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