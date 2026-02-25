module processor #(
    parameter INIT = "",
    parameter WIDTH = 32,
    parameter DEPTH = 16384
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
    logic [ADDR_WIDTH - 1:0] addrRead = 0;
    logic [ADDR_WIDTH - 1:0] addrWrite = 0;
    logic [WIDTH - 1:0] dataOut;
    logic [WIDTH - 1:0] dataIn;

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

    //Immediate values for different types of instructions
    logic [31:0] Uimm;
    logic [31:0] Iimm;
    logic [31:0] Simm;
    logic [31:0] Bimm;
    logic [31:0] Jimm;

    //Register fields from instruction decoding
    logic [31:0] rs1;
    logic [31:0] rs2;

    //Alu output 
    logic [31:0] aluOut;

    //Writeback data and its states
    logic [31:0] writeBackData;
    logic writeBackEnable = 0;

    //Computed writeback and pc values from alu 
    logic [31:0] nextPcCandidate;
    logic [31:0] writeBackDataCandidate;

    //Computed memory address for loads and stores
    logic [31:0] memAddr;

    //Word written to word addressed bram and the mask 
    logic [31:0] storeWord;
    //logic [31:0] storeMask;

    //Computes minimum bits needed for the mem addresses using log_2(depth)
    localparam ADDR_WIDTH=$clog2(DEPTH);

    //FSM states
    localparam HALT = 3'b000;
    localparam INITIAL = 3'b001;
    localparam FETCH = 3'b010;
    localparam DECODE = 3'b011;
    localparam EXECUTE = 3'b100;
    localparam MEMORY = 3'b101;
    localparam WRITE_BACK = 3'b110;

    //Initializing the state to start at HALT
    logic [3:0] state = HALT; 

    //Declare and initialize the registerFile using a file of 32 lines of 32'b0
    logic [31:0] registerFile [0:31];

    initial 
        begin
            $readmemh("register_init.txt", registerFile);
        end

    //Debugging signal
    logic isFetch = 0;

    //Instatiate the bram (simple dual port)
    bram_sdp #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .INIT(INIT)
    ) bram_inst (
        .clockWrite(clock),
        .clockRead(clock),
        .writeEnable,
        .readEnable,
        .addrWrite(addrWrite),
        .addrRead(addrRead),
        .dataIn(dataIn),
        .dataOut(dataOut)
    );

    //Instantiate the decoder (purely combinatorial)
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

    //Instantiate the alu (purely combinatorial)
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

    //Continously drive both registers from decoded idx 
    assign rs1 = registerFile[rs1Id];
    assign rs2 = registerFile[rs2Id];

    //Continously drive the target memory address (used by loads and stores)
    assign memAddr = rs1 + (isLoad ? Iimm : Simm);

    logic [31:0] loadData;
    logic [31:0] loadHalf;

    
    
    always @(*)
        begin

            loadData = {{24{byteData[7]}}, byteData};
            case(memAddr[1:0])
                0: byteData = dataOut[7:0];
                1: byteData = dataOut[15:8];
                2: byteData = dataOut[23:16];
                3: byteData = dataOut[31:24];
            endcase

        end
    // memAddr[1:0] == 0 ? dataOut[7:0] :
    //                    memAddr[1:0] == 1 ? dataOut[15:8] :
    //                    memAddr[1:0] == 2 ? dataOut[23:16] :
    //                                         dataOut[31:24];

    // logic [31:0] loadData = {{24{byteData[7]}}, byteData};


    //not working
    // always @(*)
    //     begin
    //         if (funct3 === 3'b000)
    //             begin
    //                 storeWord[15:0] = {rs2[7:0], rs2[7:0], rs2[7:0], rs2[7:0]};

    //                 case(memAddr[1:0])
    //                     0: storeMask = {24'b0, 8'b1};
    //                     1: storeMask = {16'b0, 8'b1, 8'b0};
    //                     2: storeMask = {8'b0, 8'b1, 16'b0};
    //                     3: storeMask = {8'b1, 24'b0};
    //                 endcase
    //             end

    //         if (funct3 === 3'b001)
    //             begin
    //                 storeWord[15:0] = {rs2[15:0], rs2[15:0]};

    //                 case(memAddr[1])
    //                     0: storeMask = {16'b0, 16'b1};
    //                     1: storeMask = {16'b1, 16'b0};
    //                 endcase
    //             end

    //         if (funct3 === 3'b010)
    //             begin
    //                 storeWord = rs2;
    //                 storeMask {32'b0}
    //             end
    //     end

    always @(*)
        begin
            if (funct3 == 3'b000)
                begin
                    case(memAddr[1:0])
                        0: storeWord[7:0]   = rs2[7:0];
                        1: storeWord[15:8]  = rs2[7:0];
                        2: storeWord[23:16] = rs2[7:0];
                        3: storeWord[31:24] = rs2[7:0];
                    endcase
                end
            
            else if (funct3 == 3'b001)
                begin
                    case(memAddr[1:0])
                        0: storeWord[15:0]   = rs2[15:0];
                        3: storeWord[31:16] = rs2[15:0];
                    endcase
                end

            else if (funct3 == 3'b010)
                begin
                    storeWord = rs2;
                end
        end

    //Finite State Machine
    //Based on 
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

                        //Use the second bit because we increment by 4 for the pc. 
                        //the 2 bit corresponds to the start of our word addresses

                        addrRead <= pc[ADDR_WIDTH - 1:2];

                        //Schdule readEnable and isFetch to go up and
                        //writeBackEnable to go down at posedge of next
                        //clock cycle
                        readEnable <= 1;
                        isFetch <= 1;
                        writeBackEnable <= 0;

                        state <= FETCH;
                    end
                FETCH:
                    begin
                        $display("FETCH");

                        //Schedule readEnable to go down at posedge of next clock cycle
                        readEnable <= 0;

                        //Read from PC + imm (computed by alu)
                        addrRead <= nextPcCandidate[ADDR_WIDTH - 1:2];

                        //Schedule isFetch debug signal to down at posedge of next clock cycle
                        isFetch <= 0;

                        state <= DECODE;
                    end
                DECODE: 
                    begin
                        $display("DECODE");

                        //calculate branch and jump targets here
                        instr <= dataOut; 

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
                        
                        if (isStore || isLoad)
                            begin
                                readEnable <= 1;
                            end
                        
                        state <= MEMORY;	          
                    end
                MEMORY:
                    begin
                        $display("MEM");
                        //schedule so that read and write enable to go down
                        //writes to mem

                        if(isStore) 
                            begin
                                addrWrite <= memAddr[ADDR_WIDTH - 1:2];
                                dataIn <= storeWord;
                                writeEnable <= 1;
                            end

                        if (!isLoad)
                            begin
                                writeBackData <= writeBackDataCandidate;
                            end
                        else
                            begin
                                writeBackData <= loadData;
                            end

                        writeBackEnable <= (!isBranch && !isStore);

                        readEnable <= 0;

                        state <= WRITE_BACK;
                    end
                WRITE_BACK:
                    begin
                        $display("WB");
                        //writes to register file

                        if(writeBackEnable && rdId !== 0) 
                            begin
                                registerFile[rdId] <= writeBackData;

                                `ifdef SIMULATION	 
                                          $display("x%0d <= %b",rdId,writeBackData);
                                `endif
                            end

                        if (isStore)
                            begin
                                addrRead <= pc[ADDR_WIDTH - 1:2];
                            end

                        writeBackEnable <= 0;
                        readEnable <= 1;
                        writeEnable <= 0;

                        isFetch <= 1;
                        state <= FETCH;
                    end
            endcase
        end

    `ifdef SIMULATION
        always @(posedge clock) 
            begin
                if (isFetch)
                    begin
                        $display("PC=%0d instr=%h", pc, instr);
                        $display("Instruction opcode %b", dataOut[6:0]);
                    end
                
                case (isFetch)
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