module processor #(
    parameter WIDTH = 32,
    parameter DEPTH = 16384,
    parameter ADDR_WIDTH = 32,
    parameter RESET_ADDRESS = 32'h00008000
) (
    input logic clockIn,
    input logic resetIn,
    input logic stallIn, //not used because processor not pipelined
    input logic acknowledgedIn,
    input logic [WIDTH - 1:0] dataIn,
    output logic [WIDTH - 1:0] dataOut,
    output logic [ADDR_WIDTH - 1:0] addrOut,
    output logic [3:0] selectOut,
    output logic writeEnableOut,
    output logic strobeOut,
    output logic cycleOut
);
    //Constants

    //NOP = addi zero, zero, 0, using add could have the same behavior?,
    //which would make the NOP = 32'h00000033
    localparam NOP = 32'h00000013;
    localparam EBREAK = 32'h00100073;

    //Program counters

    //address being requested this cycle
    logic [31:0] pc;

    //branch, jump or auipc targets computed in DE state
    logic [31:0] pcPlusImm;

    //JALR target from alu
    logic [31:0] pcJALR;

    //Flag to decide to branch or not
    logic takeBranch;

    //Flags that compute comparison (done in alu)
    logic isEQ;
    logic isLTU;
    logic isLT;

    //ALU inputs
    logic [31:0] aluIn1;
    logic [31:0] aluIn2;

    //Instruction register
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
    logic isEBREAK;
    logic isECALL;
    logic isCSRRS;

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
    logic writeBackEnable = 0;
    logic [31:0] writeBackData;

    //Computed memory address for loads and stores
    logic [31:0] loadAddr;
    logic [31:0] storeAddr;

    //Word written to word addressed bram and the mask 
    logic [31:0] storeData;
    logic [3:0] storeMask;

    //Word loaded to register using combinatorial logic
    logic [31:0] loadData;

    //CSR Registers
    logic [63:0] cycles;
    logic [63:0] instrRetired;

    //FSM states
    typedef enum {
        HALT,
        INITIAL,
        FETCH,
        DECODE,
        EXECUTE,
        MEMORY,
        WRITE_BACK
    } state_t;

    //Declare the state to start at INITIAL when there is a reset signal
    state_t state; 

    //Declare and initialize the registerFile using a file of 32 lines of 32'b0
    logic [31:0] registerFile [0:31];

    initial 
        begin
            $readmemh("register_init.mem", registerFile);
        end
    
    integer i;

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
        .isEBREAK,
        .isECALL,
        .isCSRRS,
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
        .aluIn1,
        .aluIn2,
        .instr5(instr[5]),
        .instr30(instr[30]),
        .funct3,
        .pcJALR,
        .aluOut,
        .isEQ,
        .isLTU,
        .isLT
    );

    //Instantiate the lsu (purely combinatorial)
    lsu #(
        .WIDTH(WIDTH)
    ) lsu_inst (
        .loadAddr,
        .storeAddr,
        .rs2,
        .dataRead,
        .funct3Load(funct3),
        .funct3Store(funct3),
        .storeData(storeData),
        .loadData(loadData),
        .storeMask(storeMask)
    );

    always_comb
        begin
            case (Iimm[11:0])
                12'hc00: csrData = cycles[31:0];
                12'hc80: csrData = cycles[63:32];
                12'hc02: csrData = instrRetired[31:0];
                12'hc82: csrData = instrRetired[63:32];

                default: csrData = 32'h0;
            endcase
        end

    always_comb
        begin
            //Branch decision logic 
            case(funct3)
                3'b000: takeBranch = isEQ;
                3'b001: takeBranch = !isEQ;
                3'b100: takeBranch = isLT;
                3'b101: takeBranch = !isLT;
                3'b110: takeBranch = isLTU;
                3'b111: takeBranch = !isLTU;

                default: takeBranch = 0;
            endcase
        end

    //Reset control + FSM
    always_ff @(posedge clockIn)
        begin
            if (resetIn)
                begin
                    for (i = 0; i < 32; i = i + 1)
                        begin
                            registerFile[i] <= 32'd0;
                        end

                    pc <= RESET_ADDRESS;

                    loadAddr <= 0;
                    storeAddr <= 0;

                    writeBackEnable <= 0;

                    cycles <= 0;
                    instrRetired <= 0;
                    isCSRRS <= 0;

                    //Set up initial read
                    addrOut <= RESET_ADDRESS;
                    dataOut <= 0;
                    selectOut <= 0;
                    writeEnableOut <= 0;
                    strobeOut <= 1;
                    cycleOut <= 1;

                    state <= INITIAL;
                end
            else 
                begin
                    cycles <= cycles + 1;

                    case(state)
                        HALT: 
                            begin
                                state <= HALT;
                            end
                        INITIAL:
                            begin
                                //Prevent read at posedge of next clock cycle
                                strobeOut <= 0;
                                cycleOut <= 0;

                                state <= FETCH;
                            end
                        FETCH:
                            begin
                                //Register data response from BRAM
                                if (acknowledgedIn)
                                    begin
                                        instr <= dataIn;
                                    end

                                state <= DECODE;
                            end
                        DECODE: 
                            begin
                                //Calculate Branch, JAL and AUIPC targets here
                                //PC value + immediate based on isTYPE flags
                                pcPlusImm <= pc + (isJAL ? Jimm[31:0] :
                                            isAUIPC ? Uimm[31:0] :
                                            Bimm[31:0]);

                                if (isEBREAK) 
                                    begin
                                        state <= HALT;
                                    end
                                else
                                    begin
                                        state <= EXECUTE;
                                    end
                            end
                        EXECUTE: 
                            begin
                                //Compute values for the writeback and the next program counter
                                if (!isSYSTEM)
                                    begin
                                        if ((isBranch && takeBranch) || isJAL)
                                            begin
                                                pc <= pcPlusImm;
                                            end
                                        else if (isJALR)
                                            begin
                                                pc <= pcJALR;
                                            end
                                        else
                                            begin
                                                pc <= pcPlus4;
                                            end
                                    end

                                if (isJAL || isJALR) 
                                    begin
                                        writeBackData <= pcPlus4;
                                    end
                                else if (isLUI)
                                    begin
                                        writeBackData <= Uimm;
                                    end
                                else if (isAUIPC)
                                    begin 
                                        writeBackData <= pcPlusImm;
                                    end
                                else if (isCSRRS)
                                    begin
                                        writeBackData <= csrData;
                                    end
                                else
                                    begin
                                        writeBackData <= aluOut;
                                    end
                                
                                //If instruction is load, schedule a read
                                //otherwise schedule a memory write
                                if (isLoad) 
                                    begin
                                        addrOut <= loadAddr;
                                        writeEnableOut <= 0;
                                        strobeOut <= 1;
                                        cycleOut <= 1;
                                    end
                                else if(isStore) 
                                    begin
                                        addrOut <= storeAddr;
                                        dataOut <= storeData;
                                        selectOut <= storeMask;
                                        writeEnableOut <= 1;
                                        strobeOut <= 1;
                                        cycleOut <= 1;
                                    end

                                //Schedule a writeback by driving writeBackEnable for one cycle
                                writeBackEnable <= (!isBranch && !isStore);
                                
                                state <= MEMORY;	          
                            end
                        MEMORY:
                            begin
                                //Read next instruction (PC updated in EXEC)
                                addrOut <= pc;
                                writeEnableOut <= 0;

                                strobeOut <= 1;
                                cycleOut <= 1;

                                state <= WRITE_BACK;
                            end
                        WRITE_BACK:
                            begin
                                if (isLoad && rdId != 0)
                                    begin
                                        //Write to register with loaded word 
                                        registerFile[rdId] <= loadData;
                                    end
                                else if(writeBackEnable && rdId != 0) 
                                    begin
                                        //Write back to register with data 
                                        //derived in EXEC
                                        registerFile[rdId] <= writeBackData;
                                    end

                                if (instr != NOP)
                                    begin
                                        instrRetired <= instrRetired + 1;

                                        // $display("%h", instr);
                                    end

                                //at next clock cycle:
                                //Stop writeback
                                writeBackEnable <= 0;

                                //Prevent read
                                strobeOut <= 0;
                                cycleOut <= 0;

                                state <= FETCH;
                            end
                    endcase
                end
        end

endmodule