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
        .instr(d_effectiveInstr),
        .isALUreg(d_isALUreg),
        .isALUimm(d_isALUimm),
        .isBranch(d_isBranch),
        .isJALR(d_isJALR),
        .isJAL(d_isJAL),
        .isAUIPC(d_isAUIPC),
        .isLUI(d_isLUI),
        .isLoad(d_isLoad),
        .isStore(d_isStore),
        .isSYSTEM(d_isSYSTEM),
        .isEBREAK(d_isEBREAK),
        .isECALL(d_isECALL),
        .isCSRRS(d_isCSRRS),
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
        .instr5(e_effectiveInstr[5]),
        .instr30(e_effectiveInstr[30]),
        .funct3(e_funct3),
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
        .loadAddr(w_loadAddr),
        .storeAddr(e_storeAddr),
        .rs2(de_rs2),
        .dataRead(dataRead),
        .funct3Load(mw_funct3),
        .funct3Store(e_funct3),
        .storeData(e_storeData),
        .loadData(w_loadData),
        .storeMask(e_storeMask)
    );

    //Continously drive ALU inputs
    assign aluIn1 = de_rs1;
    assign aluIn2 = (e_isALUreg || e_isBranch) ? de_rs2 : e_Iimm;
    
    //Continously drive bubbled instructions
    assign d_effectiveInstr = d_instr;
    assign e_effectiveInstr = de_instr;
    assign m_effectiveInstr = em_instr;
    assign w_effectiveInstr = mw_instr;
                  
    //Continously drive the target memory address (used by loads and stores)
    assign w_loadAddr = mw_loadAddr;
    assign e_storeAddr = de_storeAddr;

    //Continously drive the instruction fetched
    assign d_instr = dataRead;

    //Continously drive the value of the pc for next instruction
    assign f_pcPlus4 = f_pc + 4;

    assign readEnable = (f_readEnable || em_readEnable) && !em_writeEnable;
    assign addrRead = em_readEnable ? em_addrRead : (f_readEnable ? f_addrRead : 0);

    //Continously drive external BRAM signals using EXEC -> MEM signals
    assign writeEnable = em_writeEnable;
    assign addrWrite = em_addrWrite;
    assign dataWrite = em_dataWrite;

    //Continously drive the mask for a store to BRAM
    assign bramWriteMask = em_storeMask; 

    logic [31:0] e_csrData;

    always_comb
        begin
            case (e_Iimm[11:0])
                12'hc00: e_csrData = cycles[31:0];
                12'hc80: e_csrData = cycles[63:32];
                12'hc02: e_csrData = instrRetired[31:0];
                12'hc82: e_csrData = instrRetired[63:32];

                default: e_csrData = 32'h0;
            endcase
        end

    always_comb
        begin
            //Branch decision logic 
            case(e_funct3)
                3'b000: e_takeBranch = e_isEQ;
                3'b001: e_takeBranch = !e_isEQ;
                3'b100: e_takeBranch = e_isLT;
                3'b101: e_takeBranch = !e_isLT;
                3'b110: e_takeBranch = e_isLTU;
                3'b111: e_takeBranch = !e_isLTU;

                default: e_takeBranch = 0;
            endcase
        end

    //Reset control
    always_ff @(posedge clock)
        begin
            if (reset)
                begin
                    for (i = 0; i < 32; i = i + 1)
                        begin
                            registerFile[i] <= 32'd0;
                        end

                    f_pc <= 0; fd_pc <= 0; de_pc <= 0;
                    fd_nextPc <= 0; de_nextPc <= 0; em_nextPc <= 0; mw_nextPc <= 0; 

                    de_pcPlusImm <= 0;

                    de_instr <= NOP; em_instr <= NOP; mw_instr <= NOP; 

                    de_rs1 <= 0;
                    de_rs2 <= 0;

                    de_loadAddr <= 0; em_loadAddr <= 0; mw_loadAddr <= 0;
                    de_storeAddr <= 0;

                    f_addrRead <= 0; em_addrRead <= 0;
                    f_readEnable <= 1; em_readEnable <= 0;  

                    em_rdId <= 0; mw_rdId <= 0;
                    em_funct3 <= 0; mw_funct3 <= 0;

                    em_isLoad <= 0; mw_isLoad <= 0;
                    em_isStore <= 0; 

                    em_writeEnable <= 0;
                    //em_dataRead <= 0;
                    em_addrWrite <= 0;
                    em_dataWrite <= 0;
                    em_storeMask <= 0;

                    em_writeBackData <= 0; mw_writeBackData <= 0;
                    em_writeBackEnable <= 0; mw_writeBackEnable <= 0;

                    cycles <= 0;
                    instrRetired <= 0;

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
                                f_pc <= RESET_ADDRESS;
                                f_addrRead <= RESET_ADDRESS;
                                f_readEnable <= 1; 

                                state <= FETCH;
                            end
                        FETCH:
                            begin
                                //Schedule readEnable to go down at posedge of next clock cycle
                                f_readEnable <= 0;

                                fd_pc <= f_pc;
                                fd_nextPc <= f_pcPlus4;

                                state <= DECODE;
                            end
                        DECODE: 
                            begin
                                //Calculate Branch, JAL and AUIPC targets here
                                //PC value + immediate based on isTYPE flags
                                de_pcPlusImm <= fd_pc + (d_isJAL ? d_Jimm[31:0] :
                                            d_isAUIPC ? d_Uimm[31:0] :
                                            d_Bimm[31:0]);

                                de_nextPc <= fd_nextPc;
                                de_pc <= fd_pc;
                                de_instr <= d_effectiveInstr;

                                de_loadAddr <= registerFile[d_rs1Id] + d_Iimm;
                                de_storeAddr <= registerFile[d_rs1Id] + d_Simm;

                                de_rs1 <= registerFile[d_rs1Id];
                                de_rs2 <= registerFile[d_rs2Id];


                                if (d_isEBREAK) 
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
                                
                                if ((e_isBranch && e_takeBranch) ||  e_isJAL)
                                    begin
                                        em_nextPc <= de_pcPlusImm;
                                    end
                                else if (e_isJALR)
                                    begin
                                        em_nextPc <= e_pcJALR;
                                    end
                                else
                                    begin
                                        em_nextPc <= de_nextPc;
                                        // em_nextPc <= f_pcPlus4;
                                    end


                                if (e_isALUreg || e_isALUimm)
                                    begin
                                        em_writeBackData <= e_aluOut;
                                    end
                                else if (e_isJAL || e_isJALR) 
                                    begin
                                        em_writeBackData <= de_nextPc;
                                    end
                                else if (e_isLUI)
                                    begin
                                        em_writeBackData <= e_Uimm;
                                    end
                                else if (e_isAUIPC)
                                    begin 
                                        em_writeBackData <= de_pcPlusImm;
                                    end
                                else if (e_isCSRRS)
                                    begin
                                        em_writeBackData <= e_csrData;
                                    end
                                else
                                    begin
                                        em_writeBackData <= 32'd0;
                                    end
                                
                                //If instruction is load, schedule a read
                                //otherwise schedule a memory write
                                if (e_isLoad) 
                                    begin
                                        em_readEnable <= 1;
                                        em_addrRead <= de_loadAddr;
                                    end
                                else if (e_isStore) 
                                    begin
                                        em_addrWrite <= de_storeAddr;
                                        em_dataWrite <= e_storeData;
                                        em_storeMask <= e_storeMask;
                                        em_writeEnable <= 1;
                                    end

                                em_writeBackEnable <= (e_isALUreg ||
                                                       e_isALUimm ||
                                                       e_isJAL ||
                                                       e_isJALR ||
                                                       e_isLUI ||
                                                       e_isAUIPC ||
                                                       e_isCSRRS);

                                em_rdId <= e_rdId;
                                em_funct3 <= e_funct3;

                                em_isLoad <= e_isLoad;
                                em_isStore <= e_isStore;

                                em_loadAddr <= de_loadAddr;
                                em_instr <= e_effectiveInstr;

                                if (e_isEBREAK) 
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
                                //Schedule a writeback by driving writeBackEnable for one cycle
                                mw_writeBackEnable <= em_writeBackEnable;

                                //Stop reading or writing at the WB state
                                if (em_isLoad)
                                    begin
                                        em_readEnable <= 0;
                                    end
                                else if (em_isStore)
                                    begin
                                        em_writeEnable <= 0;
                                    end

                                mw_rdId <= em_rdId;
                                mw_funct3 <= em_funct3;

                                mw_isLoad <= em_isLoad;
                                mw_nextPc <= em_nextPc;
                                mw_loadAddr <= em_loadAddr;

                                mw_writeBackData <= em_writeBackData;

                                mw_instr <= m_effectiveInstr;

                                state <= WRITE_BACK;
                            end
                        WRITE_BACK:
                            begin
                                if (mw_isLoad && mw_rdId != 0)
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

                                //Read next instruction
                                f_pc <= mw_nextPc;
                                f_addrRead <= mw_nextPc;
                                f_readEnable <= 1;

                                //Stop writeback at next clock cycle
                                mw_writeBackEnable <= 0;

                                instrRetired <= instrRetired + 1;

                                // $display("%h", w_effectiveInstr);

                                state <= FETCH;
                            end
                    endcase
                end
        end

endmodule