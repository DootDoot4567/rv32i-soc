module processor2 #(
    parameter WIDTH = 32,
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
    logic [31:0] f_pc;

    //pipelined registers holding the pc at DE and EXEC states
    logic [31:0] fd_pc;
    logic [31:0] de_pc;

    //branch, jump or auipc targets computed in DE state
    logic [31:0] de_pcPlusImm;

    //JALR target from alu
    logic [31:0] e_pcJALR;

    //Flag to decide to branch or not
    logic e_takeBranch;

    //Flags that compute comparison (done in alu)
    logic e_isEQ;
    logic e_isLTU;
    logic e_isLT;

    //ALU inputs
    logic [31:0] aluIn1;
    logic [31:0] aluIn2;

    //Instruction register and its variants (bubbled)
    logic [31:0] fd_instr;
    logic [31:0] de_instr;
    logic [31:0] em_instr;
    logic [31:0] mw_instr;

    //Boolean flags used by the decoder, processor, and alu
    logic d_isOP;
    logic d_isOP_IMM;
    logic d_isBRANCH;
    logic d_isJALR;
    logic d_isJAL;
    logic d_isAUIPC;
    logic d_isLUI;
    logic d_isLOAD;
    logic d_isSTORE;
    logic d_isSYSTEM;

    logic de_isOP;
    logic de_isOP_IMM;
    logic de_isBRANCH;
    logic de_isJALR;
    logic de_isJAL;
    logic de_isAUIPC;
    logic de_isLUI;
    logic de_isLOAD;
    logic de_isSTORE;
    logic de_isSYSTEM;

    logic em_isLOAD;
    logic mw_isLOAD;

    logic em_isSTORE;

    //Indexes for input registers and rd register
    logic [4:0] d_rs1Id;
    logic [4:0] d_rs2Id;
    logic [4:0] d_rdId;

    logic [4:0] de_rs1Id;
    logic [4:0] de_rs2Id;
    logic [4:0] de_rdId;

    logic [4:0] em_rdId;

    logic [4:0] mw_rdId;

    //Optional opcode fields for instruction
    logic [2:0] d_funct3;
    logic [6:0] d_funct7;

    logic [2:0] de_funct3;
    logic [6:0] de_funct7;

    logic [2:0] em_funct3;

    logic [2:0] mw_funct3;

    //Immediate values for different types of instructions
    logic [31:0] d_Uimm;
    logic [31:0] d_Iimm;
    logic [31:0] d_Simm;
    logic [31:0] d_Bimm;
    logic [31:0] d_Jimm;

    logic [31:0] de_Uimm;
    logic [31:0] de_Iimm;

    //Alu output 
    logic [31:0] e_aluOut;

    //Writeback data and its states
    logic [31:0] em_writeBackData;
    logic [31:0] mw_writeBackData;

    logic em_writeBackEnable;
    logic mw_writeBackEnable;

    //Computed memory address for loads and stores
    logic [31:0] de_loadAddr;
    logic [31:0] de_storeAddr;

    logic [31:0] em_loadAddr;

    logic [31:0] mw_loadAddr;

    //Word written to word addressed bram and the mask 
    logic [31:0] e_storeData;
    logic [3:0] e_storeMask;

    //Word loaded to register using combinatorial logic
    logic [31:0] w_loadData;

    //CSR Registers
    logic [31:0] csrData;
    logic [63:0] cycles;
    logic [63:0] instrRetired;
    logic de_isCSRRS;

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

    int i;

    //Instantiate the decoder (purely combinatorial) -- DECODE STATE
    decoder decoder_inst_d (
        .instr(fd_instr),
        .isOP(d_isOP),
        .isOP_IMM(d_isOP_IMM),
        .isBRANCH(d_isBRANCH),
        .isJALR(d_isJALR),
        .isJAL(d_isJAL),
        .isAUIPC(d_isAUIPC),
        .isLUI(d_isLUI),
        .isLOAD(d_isLOAD),
        .isSTORE(d_isSTORE),
        .isSYSTEM(d_isSYSTEM),
        .rs1Id(d_rs1Id),
        .rs2Id(d_rs2Id),
        .rdId(d_rdId),
        .funct3(d_funct3),
        .funct7(d_funct7),
        .Uimm(d_Uimm),
        .Iimm(d_Iimm),
        .Simm(d_Simm),
        .Bimm(d_Bimm),
        .Jimm(d_Jimm)
    );

    //Instantiate the alu (purely combinatorial)
    alu alu_inst (
        .aluIn1(aluIn1),
        .aluIn2(aluIn2),
        .instr5(de_instr[5]),
        .instr30(de_funct7[5]),
        .funct3(de_funct3),
        .pcJALR(e_pcJALR),
        .aluOut(e_aluOut),
        .isEQ(e_isEQ),
        .isLTU(e_isLTU),
        .isLT(e_isLT)
    );

    //Instantiate the lsu (purely combinatorial)
    lsu #(
        .WIDTH(WIDTH)
    ) lsu_inst (
        .loadAddr(mw_loadAddr),
        .storeAddr(de_storeAddr),
        .rs2(registerFile[de_rs2Id]),
        .dataRead(dataIn),
        .funct3Load(mw_funct3),
        .funct3Store(de_funct3),
        .storeData(e_storeData),
        .loadData(w_loadData),
        .storeMask(e_storeMask)
    );

    always_comb
        begin
            case (de_Iimm[11:0])
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
            case(de_funct3)
                3'b000: e_takeBranch = e_isEQ;
                3'b001: e_takeBranch = !e_isEQ;
                3'b100: e_takeBranch = e_isLT;
                3'b101: e_takeBranch = !e_isLT;
                3'b110: e_takeBranch = e_isLTU;
                3'b111: e_takeBranch = !e_isLTU;

                default: e_takeBranch = 0;
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

                    f_pc <= RESET_ADDRESS;

                    fd_pc <= 0;
                    fd_instr <= NOP;

                    de_pc <= 0;
                    de_instr <= NOP;
                    de_pcPlusImm <= 0;
                    de_loadAddr <= 0; 
                    de_storeAddr <= 0;
                    de_isOP <= 0;
                    de_isOP_IMM <= 0;
                    de_isBRANCH <= 0;
                    de_isJALR <= 0;
                    de_isJAL <= 0;
                    de_isAUIPC <= 0;
                    de_isLUI <= 0;
                    de_isLOAD <= 0;
                    de_isSTORE <= 0;
                    de_isSYSTEM <= 0;
                    de_isCSRRS <= 0;
                    de_rs1Id <= 0;
                    de_rs2Id <= 0;
                    de_rdId <= 0;
                    de_funct3 <= 0;
                    de_funct7 <= 0;
                    de_Uimm <= 0;
                    de_Iimm <= 0;

                    em_instr <= NOP;
                    em_loadAddr <= 0;
                    em_isLOAD <= 0;
                    em_isSTORE <= 0; 
                    em_rdId <= 0;
                    em_funct3 <= 0;
                    em_writeBackEnable <= 0;
                    em_writeBackData <= 0; 

                    mw_instr <= NOP; 
                    mw_loadAddr <= 0;
                    mw_isLOAD <= 0;
                    mw_rdId <= 0;
                    mw_funct3 <= 0;
                    mw_writeBackEnable <= 0;
                    mw_writeBackData <= 0;

                    aluIn1 <= 0;
                    aluIn2 <= 0;

                    cycles <= 0;
                    instrRetired <= 0;

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
                                        fd_instr <= dataIn;
                                    end

                                fd_pc <= f_pc;

                                state <= DECODE;
                            end
                        DECODE: 
                            begin
                                //Calculate Branch, JAL and AUIPC targets here
                                //PC value + immediate based on isTYPE flags
                                de_pcPlusImm <= fd_pc + (d_isJAL ? d_Jimm :
                                    (d_isAUIPC ? d_Uimm : d_Bimm));

                                de_loadAddr <= registerFile[d_rs1Id] + d_Iimm;
                                de_storeAddr <= registerFile[d_rs1Id] + d_Simm;

                                aluIn1 <= registerFile[d_rs1Id];
                                aluIn2 <= (d_isOP || d_isBRANCH) ? registerFile[d_rs2Id] : d_Iimm;

                                de_pc <= fd_pc;
                                de_instr <= fd_instr;

                                de_isOP <= d_isOP;
                                de_isOP_IMM <= d_isOP_IMM;
                                de_isBRANCH <= d_isBRANCH;
                                de_isJALR <= d_isJALR;
                                de_isJAL <= d_isJAL;
                                de_isAUIPC <= d_isAUIPC;
                                de_isLUI <= d_isLUI;
                                de_isLOAD <= d_isLOAD;
                                de_isSTORE <= d_isSTORE;
                                de_isSYSTEM <= d_isSYSTEM;
                                de_isCSRRS <= d_isSYSTEM && (d_funct3 == 3'b010);

                                de_rs2Id <= d_rs2Id;
                                de_rdId <= d_rdId;
                                de_funct3 <= d_funct3;
                                de_funct7 <= d_funct7;
                                de_Uimm <= d_Uimm;
                                de_Iimm <= d_Iimm;

                                        state <= EXECUTE;
                                    end 
                        EXECUTE: 
                            begin
                                //Compute values for the writeback and the next program counter
                                
                                if ((de_isBRANCH && e_takeBranch) || de_isJAL)
                                    begin
                                        f_pc <= de_pcPlusImm;
                                    end
                                else if (de_isJALR)
                                    begin
                                        f_pc <= e_pcJALR;
                                    end
                                else
                                    begin
                                        f_pc <= de_pc + 4;
                                    end

                                case(1)
                                    de_isJAL: em_writeBackData <= de_pc + 4;
                                    de_isJALR: em_writeBackData <= de_pc + 4;
                                    de_isLUI: em_writeBackData <= de_Uimm;
                                    de_isAUIPC: em_writeBackData <= de_pcPlusImm;
                                    de_isCSRRS: em_writeBackData <= csrData;

                                    default: em_writeBackData <= e_aluOut;
                                endcase
                                
                                //If instruction is load, schedule a read
                                //otherwise schedule a memory write
                                if (de_isLOAD) 
                                    begin
                                        addrOut <= de_loadAddr;
                                        writeEnableOut <= 0;
                                        strobeOut <= 1;
                                        cycleOut <= 1;
                                    end
                                else if (de_isSTORE) 
                                    begin
                                        addrOut <= de_storeAddr;
                                        dataOut <= e_storeData;
                                        selectOut <= e_storeMask;
                                        writeEnableOut <= 1;
                                        strobeOut <= 1;
                                        cycleOut <= 1;
                                    end

                                //Schedule a writeback by driving writeBackEnable
                                em_writeBackEnable <= (de_isOP ||
                                                       de_isOP_IMM ||
                                                       de_isJAL ||
                                                       de_isJALR ||
                                                       de_isLUI ||
                                                       de_isAUIPC ||
                                                       de_isCSRRS);

                                em_rdId <= de_rdId;
                                em_funct3 <= de_funct3;

                                em_isLOAD <= de_isLOAD;
                                em_isSTORE <= de_isSTORE;

                                em_loadAddr <= de_loadAddr;
                                em_instr <= de_instr;

                                if (de_instr == EBREAK) 
                                    begin
                                        state <= HALT;
                                    end
                                else
                                    begin
                                        state <= MEMORY;
                                    end          
                            end
                        MEMORY:
                            begin
                                mw_writeBackEnable <= em_writeBackEnable;
                                mw_writeBackData <= em_writeBackData;

                                mw_rdId <= em_rdId;
                                mw_funct3 <= em_funct3;

                                mw_isLOAD <= em_isLOAD;
                                mw_loadAddr <= em_loadAddr;

                                mw_instr <= em_instr;

                                //Read next instruction (PC updated in EXEC)
                                addrOut <= f_pc;
                                writeEnableOut <= 0;

                                strobeOut <= 1;
                                cycleOut <= 1;

                                state <= WRITE_BACK;
                            end
                        WRITE_BACK:
                            begin
                                if (mw_isLOAD && mw_rdId != 0 && acknowledgedIn)
                                    begin
                                        //Write to register with loaded word 
                                        registerFile[mw_rdId] <= w_loadData;
                                    end
                                else if(mw_writeBackEnable && mw_rdId != 0) 
                                    begin
                                        //Write back to register with data 
                                        //derived in EXEC
                                        registerFile[mw_rdId] <= mw_writeBackData;
                                    end

                                if (mw_instr != NOP) 
                                    begin
                                        instrRetired <= instrRetired + 1;

                                        // $display("%h", w_effectiveInstr);
                                    end

                                //at next clock cycle:
                                //Stop writeback
                                mw_writeBackEnable <= 0;

                                //Prevent read
                                strobeOut <= 0;
                                cycleOut <= 0;

                                state <= FETCH;
                            end

                            default: state <= HALT;
                    endcase
                end
        end

endmodule
