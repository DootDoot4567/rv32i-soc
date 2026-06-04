module processor #(
    parameter INIT = "",
    parameter WIDTH = 32,
    parameter DEPTH = 16384,
    parameter ADDR_WIDTH = 32,
    parameter RESET_ADDRESS = 32'h00008000
) (
    input logic clock,
    input logic reset,
    input logic [WIDTH - 1:0] dataRead,

    output logic writeEnable,
    output logic readEnable,
    output logic [ADDR_WIDTH - 1:0] addrRead,
    output logic [ADDR_WIDTH - 1:0] addrWrite,
    output logic [WIDTH - 1:0] dataWrite,
    output logic [3:0] bramWriteMask
);
    //Constants

    //NOP = addi zero, zero, 0, using add could have the same behavior?,
    //which would make the NOP = 32'h00000033
    localparam NOP = 32'h00000013;

    //Depth for Branch Prediction Table (BHT)
    localparam BHT_DEPTH = 4096;

    //Address width for BHT
    localparam BHT_ADDR_WIDTH = $clog2(BHT_DEPTH);

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
    logic [ADDR_WIDTH - 1:0] f_addrRead, em_addrRead;

    //NOT USED
    logic [31:0] em_dataRead;

    //Write (BRAM & UART operation) registers (bubbled)
    logic em_writeEnable;
    //logic [ADDR_WIDTH - 1:0] em_addrWrite;
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
    logic [31:0] w_loadAddr, de_loadAddr, em_loadAddr, mw_loadAddr;
    logic [31:0] e_storeAddr, de_storeAddr, em_storeAddr, mw_storeAddr;

    //Word written to word addressed bram and the mask 
    logic [31:0] e_storeData;
    logic [3:0] e_storeMask, em_storeMask;

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

    logic e_writesRd, m_writesRd, w_writesRd;

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

    //Signal that validates the contents of decode
    logic decodeIsValid;

    //signal that prevents a fetch a cycle after a control hazard
    logic preventFetch;

    //Forwarded registers
    logic [31:0] e_rs1Forwarded;
    logic [31:0] e_rs2Forwarded;

    logic [31:0] d_rs1Forwarded;
    logic [31:0] d_rs2Forwarded;

    //Registers used to compute writeback faster and used by forwarder module 
    logic [31:0] e_result;
    logic [31:0] e_rs1;
    logic [31:0] e_rs2;

    //Branch prediction registers and signals
    logic d_predictTaken, fd_predictTaken, de_predictTaken;

    logic [1:0] bpGHT [0:BHT_DEPTH - 1];
    logic [31:0] bpPc;

    logic [BHT_ADDR_WIDTH - 1:0] bpIndex;
    logic [BHT_ADDR_WIDTH - 1:0] bpGHR;
    logic [BHT_ADDR_WIDTH - 1:0] fd_bpIndex, de_bpIndex;

    //FSM states
    typedef enum {
        HALT,
        INITIAL,
        RUN
    } state_t;

    //Memory response tracking "state"
    //tells us what dataRead contains THIS cycle,
    //based on what was requested LAST cycle
    typedef enum {
        NOTHING,
        FETCH, 
        LOAD
    } mem_resp_t;

    //Declare the state to start at INITIAL when there is a reset signal
    state_t state; 

    mem_resp_t mem_resp_state;

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
        .instr(e_effectiveInstr),
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
        .rs2(e_rs2Forwarded),
        .dataRead(dataRead),
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
        .clock,
        .reset(prefetchReset),
        .writeEnable(prefetchWriteEnable),
        .readEnable(prefetchReadEnable),
        .dataRead(prefetchDataRead),
        .dataWrite(prefetchDataWrite),
        .empty(prefetchEmpty),
        .full(prefetchFull)
    );

    //Instantiate register forwarder (purely combinational)
    reg_forwarder forwarder_inst (
        .d_rs1Id(d_rs1Id),
        .d_rs2Id(d_rs2Id),
        .e_rs1Id(e_rs1Id),
        .e_rs2Id(e_rs2Id),
        .de_rs1(de_rs1),
        .de_rs2(de_rs2),
        .rs1Data(registerFile[d_rs1Id]),
        .rs2Data(registerFile[d_rs2Id]),
        .em_rdId(em_rdId),
        .mw_rdId(mw_rdId),
        .m_writesRd(m_writesRd),
        .w_writesRd(w_writesRd),
        .em_writeBackData(em_writeBackData),
        .mw_writeBackData(mw_writeBackData),
        .mw_isLoad(mw_isLoad),
        .w_loadData(w_loadData),
        .d_rs1Forwarded(d_rs1Forwarded),
        .d_rs2Forwarded(d_rs2Forwarded),
        .e_rs1Forwarded(e_rs1Forwarded),
        .e_rs2Forwarded(e_rs2Forwarded)
    );

    //Continously drive ALU inputs
    assign aluIn1 = e_rs1Forwarded;
    assign aluIn2 = (e_isALUreg || e_isBranch) ? e_rs2Forwarded : e_Iimm;
    
    //Continously drive bubbled instructions
    assign d_effectiveInstr = (decodeIsValid) ? fd_instr : NOP;
    assign e_effectiveInstr = de_instr;
    assign m_effectiveInstr = em_instr;
    assign w_effectiveInstr = mw_instr;
                  
    //Continously drive the target memory address (used by loads and stores)
    assign w_loadAddr = mw_loadAddr;
    assign e_storeAddr = de_storeAddr;
 
    //Continously drive the data read from BRAM 
    // assign d_instr = instrPrefetched;
    // assign d_pc = pcPrefetched;

    //fetch readEnable and address are computed combinatorially
    assign f_readEnable = !stallFetch;
    assign f_addrRead = controlHazard ? f_nextPc : f_pc;

    assign readEnable = (f_readEnable || em_readEnable) && !em_writeEnable;
    assign addrRead = em_readEnable ? em_loadAddr : f_addrRead;
    
    //Continously drive external BRAM signals using EXEC -> MEM signals
    assign writeEnable = em_writeEnable;
    assign addrWrite = em_storeAddr;
    assign dataWrite = em_dataWrite;

    //Continously drive the mask for a store to BRAM
    assign bramWriteMask = em_storeMask; 

    assign d_readsRs1 = decodeIsValid && !(d_isJAL || d_isAUIPC || d_isLUI);
    assign d_readsRs2 = decodeIsValid && (d_isALUreg || d_isBranch || d_isStore);

    assign e_writesRd = (e_effectiveInstr != NOP) && !e_isStore && !e_isBranch;
    assign m_writesRd = (m_effectiveInstr != NOP) && !em_isStore && !em_isBranch;
    assign w_writesRd = (w_effectiveInstr != NOP) && !mw_isStore && !mw_isBranch;

    assign rs1Conflict = d_readsRs1 && d_rs1Id != 0 && (d_rs1Id == e_rdId) && e_writesRd;
    assign rs2Conflict = d_readsRs2 && d_rs2Id != 0 && (d_rs2Id == e_rdId) && e_writesRd;

    assign controlHazard = e_isJAL || e_isJALR || (e_takeBranch && e_isBranch) || (e_isBranch && !e_takeBranch && de_predictTaken);
    assign structuralHazard = em_readEnable || em_writeEnable;
    assign dataHazard = rs1Conflict || rs2Conflict;
    
    assign stallFetch = dataHazard || structuralHazard || prefetchFull || e_isLoad;
    assign stallDecode = dataHazard;
    
    assign flushDecode = controlHazard;
    assign flushExecute = controlHazard || dataHazard;

    assign writeBackEnable = w_writesRd && mw_rdId != 0;

    assign em_readEnable = em_isLoad;
    assign em_writeEnable = em_isStore;

    assign prefetchReset = flushDecode || reset;

    assign prefetchWriteEnable = (mem_resp_state == FETCH) && !prefetchFull && !prefetchReset && !em_readEnable && !preventFetch;
    assign prefetchDataWrite   = {capturedReqPc, dataRead};
    assign prefetchReadEnable = !prefetchEmpty && !stallDecode && !flushDecode;

    assign d_predictTaken = bpGHT[bpIndex][1];
    assign bpIndex = computeGHTIndex(f_pc);

    function automatic [BHT_ADDR_WIDTH - 1:0] computeGHTIndex;
        input [31:0] pc;
        computeGHTIndex = pc[BHT_ADDR_WIDTH + 1:2] ^ bpGHR;
    endfunction

    function automatic [BHT_ADDR_WIDTH - 1:0] updateGHR;
        input [BHT_ADDR_WIDTH - 1:0] gblHistReg;
        input taken;
        updateGHR = ({gblHistReg[BHT_ADDR_WIDTH-2:0], taken});
    endfunction

    //Saturated counter update
    function automatic [1:0] updateCounter;
        input [1:0] counter;
        input logic taken;

        if (taken)
            begin
                updateCounter = (counter == 2'b11) ? 2'b11 : counter + 1;
            end
        else
            begin
                updateCounter = (counter == 2'b00) ? 2'b00 : counter - 1;
            end
    endfunction

    always_comb 
        begin
            case (1)
                e_isALUreg: e_result = e_aluOut;
                e_isALUimm: e_result = e_aluOut;
                e_isJAL: e_result = de_pc + 4;
                e_isJALR: e_result = de_pc + 4;
                e_isLUI: e_result = e_Uimm;
                e_isAUIPC: e_result = de_pcPlusImm;
                e_isCSRRS: e_result = e_csrData;

                default: e_result = 32'd0;
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
    always_ff @(posedge clock)
        begin
            if (reset)
                begin
                    for (i = 0; i < 32; i = i + 1)
                        begin
                            registerFile[i] <= 32'd0;
                        end

                    for (i = 0; i < BHT_DEPTH; i = i + 1)
                        begin
                            bpGHT[i] <= 2'b00;
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

                    em_storeMask <= 0;
                    em_writeBackData <= 0; mw_writeBackData <= 0;

                    cycles <= 0;
                    instrRetired <= 0;
        
                    decodeIsValid <= 0;
                    capturedReqPc <= RESET_ADDRESS;
                    mem_resp_state <= NOTHING;

                    preventFetch <= 0;

                    bpGHR <= 0;
                    fd_bpIndex <= 0; de_bpIndex <= 0;
                    fd_predictTaken <= 0; de_predictTaken <= 0;

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
                                fd_pc <= RESET_ADDRESS;
                                capturedReqPc <= RESET_ADDRESS;
                                mem_resp_state <= NOTHING;

                                state <= RUN;
                            end
                        RUN:
                            begin
                                //Calculate Branch, JAL and AUIPC targets here
                                //PC value + immediate based on isTYPE flags

                                // Always capture the fetch address when fetch is requested,
                                // regardless of memory operations in flight
                                if (f_readEnable && !em_readEnable)
                                    begin
                                        mem_resp_state <= FETCH;
                                        capturedReqPc <= f_addrRead;
                                    end
                                else if (em_readEnable)
                                    begin
                                        mem_resp_state <= LOAD;
                                    end
                                else
                                    begin
                                        mem_resp_state <= NOTHING;
                                    end

                                if (prefetchReadEnable)
                                    begin
                                        fd_instr <= prefetchDataRead[31:0];
                                        fd_pc <= prefetchDataRead[63:32];
                                        fd_bpIndex <= computeGHTIndex(prefetchDataRead[63:32]);
                                        fd_predictTaken <= d_predictTaken;
                                        decodeIsValid <= 1;
                                    end
                                else if (!stallDecode || flushDecode)
                                    begin
                                        decodeIsValid <= 0;
                                    end

                                if (flushExecute) 
                                    begin
                                        de_pc <= 0;
                                        de_pcPlusImm <= 0;
                                        de_instr <= NOP;

                                        de_bpIndex <= 0;
                                        de_predictTaken <= 0;

                                        de_loadAddr <= 0;
                                        de_storeAddr <= 0;

                                        de_rs1 <= 0;
                                        de_rs2 <= 0;
                                    end
                                else if (!stallDecode)
                                    begin
                                        de_pc <= fd_pc;
                                        de_pcPlusImm <= fd_pc + (d_isJAL ? d_Jimm : (d_isAUIPC ? d_Uimm : d_Bimm));

                                        de_bpIndex <= fd_bpIndex;
                                        de_predictTaken <= fd_predictTaken;

                                        de_instr <= d_effectiveInstr;

                                        de_loadAddr <= d_rs1Forwarded + d_Iimm;
                                        de_storeAddr <= d_rs1Forwarded + d_Simm;

                                        de_rs1 <= d_rs1Forwarded;
                                        de_rs2 <= d_rs2Forwarded;
                                    end

                                preventFetch <= controlHazard;

                                if (controlHazard)
                                    begin
                                        f_pc <= f_nextPc;
                                    end
                                else if (f_readEnable)
                                    begin
                                        f_pc <= f_pc + 4;
                                    end

                                em_writeBackData <= e_result;

                                if (e_isBranch && e_effectiveInstr != NOP)
                                    begin
                                        bpGHR <= updateGHR(bpGHR, e_takeBranch);
                                        bpGHT[de_bpIndex] <= updateCounter(bpGHT[de_bpIndex], e_takeBranch); 
                                    end
                                
                                //If instruction is load, schedule a read
                                //otherwise schedule a memory write

                                em_loadAddr <= de_loadAddr;
                                em_storeAddr <= de_storeAddr;
                                em_dataWrite <= e_storeData;
                                em_storeMask <= e_storeMask;

                                em_rdId <= e_rdId;
                                em_funct3 <= e_funct3;

                                em_isLoad <= e_isLoad;
                                em_isStore <= e_isStore;
                                em_isBranch <= e_isBranch;

                                em_instr <= e_effectiveInstr;

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
                                        // mw_isLoad <= 0;
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