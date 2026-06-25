module processor #(
    parameter INIT = "",
    parameter WIDTH = 32,
    parameter DEPTH = 16384,
    parameter ADDR_WIDTH = 32,
    parameter RESET_ADDRESS = 32'h00008000
) (
    input logic clockIn,
    input logic resetIn,
    input logic stallIn,
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

    //Program counters

    //address being requested this cycle
    logic [31:0] f_pc;

    //pipelined registers holding the pc at DE and EXEC states
    logic [31:0] fd_pc, de_pc;

    //next pc after branch/jump resolution
    logic [31:0] f_nextPc;

    //branch, jump or auipc targets computed in DE state
    logic [31:0] de_pcPlusImm;

    //JALR target from alu
    logic [31:0] e_pcJALR;

    //pc value from last fetch request
    logic [31:0] capturedReqPc;

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
    logic [31:0] fd_instr, de_instr, em_instr, mw_instr;

    //Read (BRAM & UART operation) registers (bubbled)
    logic f_readEnable, em_readEnable;
    logic [ADDR_WIDTH - 1:0] f_addrRead;

    //NOT USED
    logic [31:0] em_dataRead;

    //Write (BRAM & UART operation) registers (bubbled)
    logic em_writeEnable;
    logic [31:0] em_dataWrite;

    //Boolean flags used by the decoder, processor, and alu
    logic d_isALUreg, e_isALUreg; 
    logic d_isALUimm, e_isALUimm;
    logic d_isBranch, e_isBranch, em_isBranch, mw_isBranch;
    logic d_isJALR, e_isJALR;    
    logic d_isJAL, e_isJAL;    
    logic d_isAUIPC, e_isAUIPC;    
    logic d_isLUI, e_isLUI;    
    logic d_isLoad, e_isLoad, em_isLoad, mw_isLoad;  
    logic d_isStore, e_isStore, em_isStore, mw_isStore;
    logic d_isSYSTEM, e_isSYSTEM;

    //Indexes for input registers and ra register
    logic [4:0] d_rs1Id, e_rs1Id;
    logic [4:0] d_rs2Id, e_rs2Id;
    logic [4:0] d_rdId, e_rdId, em_rdId, mw_rdId;

    //Optional opcode fields for instruction
    logic [2:0] d_funct3, e_funct3, em_funct3, mw_funct3;
    logic [6:0] d_funct7, e_funct7;

    //Immediate values for different types of instructions
    logic [31:0] d_Uimm, e_Uimm;
    logic [31:0] d_Iimm, e_Iimm;
    logic [31:0] d_Simm, e_Simm;
    logic [31:0] d_Bimm, e_Bimm;
    logic [31:0] d_Jimm, e_Jimm;

    //Environment defined variables
    logic d_isEBREAK, e_isEBREAK;
    logic d_isECALL, e_isECALL;
    logic d_isCSRRS, e_isCSRRS;

    //Register fields from instruction decoding
    logic [31:0] de_rs1, de_rs2;

    //Effective instructions (bubbled from state to state)
    logic [31:0] d_effectiveInstr, 
                 e_effectiveInstr, 
                 m_effectiveInstr, 
                 w_effectiveInstr;

    //Alu output 
    logic [31:0] e_aluOut;

    //Writeback data and its states
    logic [31:0] em_writeBackData, mw_writeBackData;
    logic writeBackEnable;

    //Computed memory address for loads and stores
    logic [31:0] de_loadAddr, em_loadAddr, mw_loadAddr;
    logic [31:0] de_storeAddr, em_storeAddr, mw_storeAddr;

    //Word written to word addressed bram and the mask 
    logic [31:0] e_storeData;
    logic [3:0] e_storeMask;

    //Word loaded to register using combinatorial logic
    logic [31:0] w_loadData;

    //CSR Registers
    logic [31:0] e_csrData;
    logic [63:0] cycles;
    logic [63:0] instrRetired;

    //Flush and stall signals
    logic flushDecode;
    logic flushExecute;
    logic stallFetch;
    logic stallDecode;

    //Hazard signals
    logic rs1Conflict;
    logic rs2Conflict;

    logic d_readsRs1;
    logic d_readsRs2;

    logic e_writesRd;
    logic m_writesRd;
    logic w_writesRd;

    logic controlHazard;
    logic structuralHazard;
    logic dataHazard;

    //Prefetch buffer signals
    logic prefetchReset;
    logic prefetchFull;
    logic prefetchEmpty;
    logic prefetchWriteEnable;
    logic prefetchReadEnable;
    logic [63:0] prefetchDataWrite;
    logic [63:0] prefetchDataRead;

    //signal that validates the contents of decode
    logic decodeIsValid;

    //signal that prevents a fetch a cycle after a control hazard
    logic preventFetch;

    //FSM states
    typedef enum {
        HALT,
        INITIAL,
        RUN
    } state_t;

    //Memory response tracking "state"
    typedef enum {
        NOTHING,
        FETCH, 
        LOAD,
        STORE
    } mem_resp_t;

    //Declare the state to start at INITIAL when there is a reset signal
    state_t state; 

    //Part of the CPU expecting a response from memory
    mem_resp_t busOwner;

    //Declare and initialize the registerFile using a file of 32 lines of 32'b0
    logic [31:0] registerFile [0:31];

    initial 
        begin
            $readmemh("register_init.mem", registerFile);
        end
    
    integer i;

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

    //Instantiate the decoder (purely combinatorial) -- EXEC STATE
    decoder decoder_inst_e (
        .instr(e_effectiveInstr),
        .isALUreg(e_isALUreg),
        .isALUimm(e_isALUimm),
        .isBranch(e_isBranch),
        .isJALR(e_isJALR),
        .isJAL(e_isJAL),
        .isAUIPC(e_isAUIPC),
        .isLUI(e_isLUI),
        .isLoad(e_isLoad),
        .isStore(e_isStore),
        .isSYSTEM(e_isSYSTEM),
        .isEBREAK(e_isEBREAK),
        .isECALL(e_isECALL),
        .isCSRRS(e_isCSRRS),
        .rs1Id(e_rs1Id),
        .rs2Id(e_rs2Id),
        .rdId(e_rdId),
        .funct3(e_funct3),
        .funct7(e_funct7),
        .Uimm(e_Uimm),
        .Iimm(e_Iimm),
        .Simm(e_Simm),
        .Bimm(e_Bimm),
        .Jimm(e_Jimm)
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
        .loadAddr(mw_loadAddr),
        .storeAddr(de_storeAddr),
        .rs2(de_rs2),
        .dataRead(dataIn),
        .funct3Load(mw_funct3),
        .funct3Store(e_funct3),
        .storeData(e_storeData),
        .loadData(w_loadData),
        .storeMask(e_storeMask)
    );
    
    //Instantiate the fifo (the prefetch buffer)
    fifo #(
        .DEPTH(16),
        .WIDTH(64)
    ) fifo_inst (
        .clock(clockIn),
        .reset(prefetchReset),
        .writeEnable(prefetchWriteEnable),
        .readEnable(prefetchReadEnable),
        .dataRead(prefetchDataRead),
        .dataWrite(prefetchDataWrite),
        .empty(prefetchEmpty),
        .full(prefetchFull)
    );

    //Continously drive ALU inputs
    assign aluIn1 = de_rs1;
    assign aluIn2 = (e_isALUreg || e_isBranch) ? de_rs2 : e_Iimm;

    //Continously drive bubbled instructions
    assign d_effectiveInstr = (decodeIsValid) ? fd_instr : NOP;
    assign e_effectiveInstr = de_instr;
    assign m_effectiveInstr = em_instr;
    assign w_effectiveInstr = mw_instr;
    
    //fetch readEnable and address are computed combinatorially
    assign f_readEnable = !stallFetch && !stallIn;;
    assign f_addrRead = controlHazard ? f_nextPc : f_pc;
    
    //Continously drive external BRAM signals using EXEC -> MEM signals
    assign dataOut = em_dataWrite;

    assign d_readsRs1 = decodeIsValid && !(d_isJAL || d_isAUIPC || d_isLUI);
    assign d_readsRs2 = decodeIsValid && (d_isALUreg || d_isBranch || d_isStore);

    assign e_writesRd = (e_effectiveInstr != NOP) && !e_isStore && !e_isBranch;
    assign m_writesRd = (m_effectiveInstr != NOP) && !em_isStore && !em_isBranch;
    assign w_writesRd = (w_effectiveInstr != NOP) && !mw_isStore && !mw_isBranch;

    assign rs1Conflict = d_readsRs1 && d_rs1Id != 0 && 
                        (((d_rs1Id == e_rdId) && e_writesRd) || 
                         ((d_rs1Id == em_rdId) && m_writesRd) ||
                         ((d_rs1Id == mw_rdId) && w_writesRd));

    assign rs2Conflict = d_readsRs2 && d_rs2Id != 0 && 
                        (((d_rs2Id == e_rdId) && e_writesRd) || 
                         ((d_rs2Id == em_rdId )&& m_writesRd) ||
                         ((d_rs2Id == mw_rdId) && w_writesRd));

    assign controlHazard = e_isJAL || e_isJALR || (e_takeBranch && e_isBranch);
    assign structuralHazard = em_isLoad || em_isStore;
    assign dataHazard = rs1Conflict || rs2Conflict;
    
    assign stallFetch = dataHazard || structuralHazard || prefetchFull || e_isLoad;
    assign stallDecode = dataHazard;
    
    assign flushDecode = controlHazard;
    assign flushExecute = controlHazard || dataHazard;

    assign writeBackEnable = w_writesRd && mw_rdId != 0;

    assign prefetchReset = flushDecode || resetIn;

    assign prefetchWriteEnable = (busOwner == FETCH) && acknowledgedIn && !prefetchFull && !prefetchReset && !em_isLoad && !preventFetch;
    assign prefetchReadEnable = !prefetchEmpty && !stallDecode && !flushDecode;

    assign strobeOut = (state == RUN) ? 1'b1 : 1'b0;
    assign cycleOut = (state == RUN) ? 1'b1 : 1'b0;

    assign prefetchDataWrite = {capturedReqPc, dataIn};

    always_comb 
        begin
            case(1)
                em_writeEnable: addrOut = em_storeAddr;
                em_readEnable: addrOut = em_loadAddr;
                f_readEnable: addrOut = f_addrRead;
            endcase
        end

    always_comb 
        begin
            if ((e_isBranch && e_takeBranch) || e_isJAL)
                begin
                    f_nextPc = de_pcPlusImm;
                end
            else if (e_isJALR)
                begin
                    f_nextPc = e_pcJALR;
                end
            else
                begin
                    f_nextPc = f_pc;
                end
        end

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

    //Reset control + FSM
    always_ff @(posedge clockIn)
        begin
            if (resetIn)
                begin
                    for (i = 0; i < 32; i = i + 1)
                        begin
                            registerFile[i] <= 32'd0;
                        end

                    f_pc <= RESET_ADDRESS; fd_pc <= 0; de_pc <= 0;

                    de_pcPlusImm <= 0;

                    fd_instr <= NOP; de_instr <= NOP; em_instr <= NOP; mw_instr <= NOP; 

                    de_rs1 <= 0; de_rs2 <= 0;                    

                    de_loadAddr <= 0; em_loadAddr <= 0; mw_loadAddr <= 0;
                    de_storeAddr <= 0; em_storeAddr <= 0; mw_storeAddr <= 0;
                    em_dataWrite <= 0;

                    em_rdId <= 0; mw_rdId <= 0;
                    em_funct3 <= 0; mw_funct3 <= 0;

                    em_isLoad <= 0; mw_isLoad <= 0;
                    em_isStore <= 0; mw_isStore <= 0;
                    em_isBranch <= 0; mw_isBranch <= 0;

                    em_readEnable <= 0;
                    em_writeEnable <= 0;
                    writeEnableOut <= 0;

                    em_writeBackData <= 0; mw_writeBackData <= 0;

                    cycles <= 0;
                    instrRetired <= 0;
        
                    decodeIsValid <= 0;
                    capturedReqPc <= RESET_ADDRESS;
                    busOwner <= NOTHING;

                    preventFetch <= 0;
                    selectOut <= 0;

                    state <= INITIAL;
                end
            else 
                begin
                    cycles <= cycles + 1;

                    // $display("%h", dataIn);

                    case(state)
                        HALT: 
                            begin
                                state <= HALT;
                            end
                        INITIAL:
                            begin
                                f_pc <= RESET_ADDRESS;
                                fd_pc <= RESET_ADDRESS;
                                capturedReqPc <= RESET_ADDRESS;
                                busOwner <= NOTHING;

                                state <= RUN;
                            end
                        RUN:
                            begin
                                //Schedule readEnable to go down for a fetch if load will and is occuring

                                if (stallIn)
                                    begin
                                        busOwner <= busOwner;
                                    end
                                else if (em_writeEnable)
                                    begin
                                        busOwner <= STORE;
                                    end
                                else if (em_readEnable)
                                    begin
                                        busOwner <= LOAD;
                                    end
                                else if (f_readEnable)
                                    begin
                                        busOwner <= FETCH;
                                        capturedReqPc <= f_addrRead;
                                    end
                                else
                                    begin
                                        busOwner <= NOTHING;
                                    end

                                if (prefetchReadEnable)
                                    begin
                                        fd_instr <= prefetchDataRead[31:0];
                                        fd_pc <= prefetchDataRead[63:32];
                                        decodeIsValid <= 1;
                                    end
                                else if (!stallDecode || flushDecode)
                                    begin
                                        decodeIsValid <= 0;
                                    end

                                if (flushExecute) 
                                    begin
                                        de_pc <= de_pc;
                                        de_pcPlusImm <= 0;
                                        de_instr <= NOP;

                                        de_loadAddr <= 0;
                                        de_storeAddr <= 0;

                                        de_rs1 <= 0;
                                        de_rs2 <= 0;
                                    end
                                else if (!stallDecode)
                                    begin
                                        de_pc <= fd_pc;
                                        de_pcPlusImm <= fd_pc + (d_isJAL ? d_Jimm : (d_isAUIPC ? d_Uimm : d_Bimm));

                                        de_instr <= d_effectiveInstr;

                                        de_loadAddr <= registerFile[d_rs1Id] + d_Iimm;
                                        de_storeAddr <= registerFile[d_rs1Id] + d_Simm;

                                        de_rs1 <= registerFile[d_rs1Id];
                                        de_rs2 <= registerFile[d_rs2Id];
                                    end

                                //Compute values for the writeback and the next program counter
                                preventFetch <= controlHazard;

                                if (controlHazard)
                                    begin
                                        f_pc <= f_nextPc;
                                    end
                                else if (f_readEnable)
                                    begin
                                        f_pc <= f_pc + 4;
                                    end

                                if (e_isALUreg || e_isALUimm)
                                    begin
                                        em_writeBackData <= e_aluOut;
                                    end
                                else if (e_isJAL || e_isJALR) 
                                    begin
                                        em_writeBackData <= de_pc + 4;
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

                                em_readEnable <= e_isLoad;
                                em_writeEnable <= e_isStore;

                                em_loadAddr <= de_loadAddr;
                                em_storeAddr <= de_storeAddr;
                                em_dataWrite <= e_storeData;
                                selectOut <= e_storeMask;

                                em_rdId <= e_rdId;
                                em_funct3 <= e_funct3;

                                em_isLoad <= e_isLoad;
                                em_isStore <= e_isStore;
                                em_isBranch <= e_isBranch;

                                em_instr <= e_effectiveInstr;
                                writeEnableOut <= e_isStore;

                                //Stop reading or writing at the WB state
                                if (em_isLoad)
                                    begin
                                        mw_loadAddr <= em_loadAddr;
                                    end
                                else if (em_isStore)
                                    begin
                                        mw_storeAddr <= em_storeAddr;
                                    end

                                mw_rdId <= em_rdId;
                                mw_funct3 <= em_funct3;

                                mw_isLoad <= em_isLoad;
                                mw_isStore <= em_isStore;
                                mw_isBranch <= em_isBranch;

                                mw_writeBackData <= em_writeBackData;

                                mw_instr <= m_effectiveInstr;

                                if (mw_isLoad && mw_rdId != 0)
                                    begin
                                        //Write to register with loaded word 
                                        registerFile[mw_rdId] <= w_loadData;
                                    end
                                else if(writeBackEnable) 
                                    begin
                                        //Write back to register with data 
                                        //derived in EXEC
                                        registerFile[mw_rdId] <= mw_writeBackData;
                                    end

                                if (w_effectiveInstr != NOP) 
                                    begin
                                        instrRetired <= instrRetired + 1;

                                        // $display("%h", w_effectiveInstr);
                                    end

                                if (e_isEBREAK || d_isEBREAK) 
                                    begin
                                        state <= HALT;
                                    end
                                else
                                    begin
                                        state <= RUN;
                                    end 
                            end
                    endcase
                end
        end

endmodule