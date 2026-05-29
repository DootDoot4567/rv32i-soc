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
    //NOP = addi zero, zero, 0, using add could have the same behavior,
    //which would make the NOP = 32'h00000033
    localparam NOP = 32'h00000013;

    //Program counter and different wires to drive different pc
    //values at different states
    logic [31:0] f_pc, fd_pc, de_pc;
    // logic [31:0] fd_nextPc, de_nextPc, em_nextPc, mw_nextPc;
    logic [31:0] f_pcPlus4;
    logic [31:0] de_pcPlusImm;
    logic [31:0] e_pcJALR;

    //Flag to decide to branch or not
    logic e_takeBranch;

    //Flags that compute comparison (done in alu)
    logic e_isEQ;
    logic e_isLTU;
    logic e_isLT;

    //Instruction register and its variants (bubbled)
    logic [31:0] d_instr, de_instr, em_instr, mw_instr;
    //THIS CHANGE IS OKAY
    // logic [31:0] fd_instr;

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
    //logic em_writeBackEnable, mw_writeBackEnable;
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
    //logic de_conflict, dm_conflict, dw_conflict, 
    logic fm_conflict, fw_conflict;
    logic e_writesRd, m_writesRd, w_writesRd;
    logic d_emw_conflict;
    logic controlHazard;
    logic structuralHazard;
    logic dataHazard;

    //logic [31:0] mw_memData; //, memData;

    //FSM states
    typedef enum {
        HALT,
        INITIAL,
        RUN
    } state_t;

    //Declaring the state to start at INITIAL when there is a reset signal
    state_t state; 

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
        .rs1(de_rs1),
        .rs2(de_rs2),
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
        .Uimm(e_Uimm),
        .Iimm(e_Iimm),
        .Simm(e_Simm),
        .Bimm(e_Bimm),
        .Jimm(e_Jimm),
        .funct3(e_funct3),
        .funct7(e_funct7),
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
    
    //Continously drive bubbled instructions
    // assign d_effectiveInstr = (fd_nop) ? NOP : fd_instr;
    //assign d_effectiveInstr = fd_instr;
    assign d_effectiveInstr = d_instr;
    assign e_effectiveInstr = de_instr;
    // assign d_effectiveInstr = (flushDecode) ? NOP : d_instr;
    // assign e_effectiveInstr = (flushExecute) ? NOP : de_instr;
    assign m_effectiveInstr = em_instr;
    assign w_effectiveInstr = mw_instr;
                  
    //Continously drive the target memory address (used by loads and stores)
    assign w_loadAddr = mw_loadAddr;
    assign e_storeAddr = de_storeAddr;
 
    //Continously drive the data read from BRAM 
    // assign memData = dataRead;
    assign d_instr = dataRead;

    // assign d_instr = instrPrefetched;
    // assign d_pc = pcPrefetched;

    //Continously drive the value of the pc for next instruction
    assign f_pcPlus4 = f_pc + 4;

    assign readEnable = (f_readEnable || em_readEnable) && !em_writeEnable;
    assign addrRead = em_readEnable ? em_loadAddr : f_addrRead;
    
    //Continously drive external BRAM signals using EXEC -> MEM signals
    assign writeEnable = em_writeEnable;
    //assign addrWrite = em_addrWrite;
    assign addrWrite = em_storeAddr;
    assign dataWrite = em_dataWrite;

    //Continously drive the mask for a store to BRAM
    assign bramWriteMask = em_storeMask; 

    logic rs1Conflict;
    logic rs2Conflict;
    logic fd_nop;

    logic d_readsRs1;
    logic d_readsRs2;

    assign d_readsRs1 = !fd_nop && !(d_isJAL || d_isAUIPC || d_isLUI);
    assign d_readsRs2 = !fd_nop && (d_isALUreg || d_isBranch || d_isStore);

    assign e_writesRd = !e_isStore && !e_isBranch;
    assign m_writesRd = !em_isStore && !em_isBranch;
    assign w_writesRd = !mw_isStore && !mw_isBranch;
    // assign w_writesRd =
    // (w_effectiveInstr != NOP) &&
    // !mw_isStore &&
    // !mw_isBranch &&
    // (mw_rdId != 5'd0);

    //assign writeBackEnable = w_writesRd;

    assign rs1Conflict = d_readsRs1 && d_rs1Id != 0 && 
                        ((d_rs1Id == e_rdId && e_writesRd) || 
                         (d_rs1Id == em_rdId && m_writesRd) ||
                         (d_rs1Id == mw_rdId && w_writesRd));

    assign rs2Conflict = d_readsRs2 && d_rs2Id != 0 && 
                        ((d_rs2Id == e_rdId && e_writesRd) || 
                         (d_rs2Id == em_rdId && m_writesRd) ||
                         (d_rs2Id == mw_rdId && w_writesRd));

    assign fm_conflict = (em_isLoad || em_isStore);
    assign fw_conflict = mw_isLoad;

    assign controlHazard = e_isJAL || e_isJALR || (e_takeBranch && e_isBranch);
    assign structuralHazard = fm_conflict || fw_conflict;
    assign dataHazard = rs1Conflict || rs2Conflict;
    
    assign stallFetch = dataHazard || structuralHazard;
    assign stallDecode = dataHazard;
    
    assign flushDecode = controlHazard;
    assign flushExecute = controlHazard || dataHazard;

    assign writeBackEnable = w_writesRd && mw_rdId != 0;
    assign fd_nop = f_readEnable;

    assign em_readEnable = em_isLoad;
    assign em_writeEnable = em_isStore;

    logic [31:0] f_nextPc;

    always_comb 
        begin
            if ((e_isBranch && e_takeBranch) || e_isJAL)
                f_nextPc = de_pcPlusImm;
            else if (e_isJALR)
                f_nextPc = e_pcJALR;
            else if (!stallFetch)
                f_nextPc = f_pc + 4;
            else
                f_nextPc = f_pc;
        end
    
    // logic f_kill_response;


    always @(*)
        begin
            case (e_Iimm[11:0])
                12'hc00:
                    begin
                        e_csrData = cycles[31:0];
                    end
                12'hc80:
                    begin
                        e_csrData = cycles[63:32];
                    end
                12'hc02:
                    begin
                        e_csrData = instrRetired[31:0];
                    end
                12'hc82:
                    begin
                        e_csrData = instrRetired[63:32];
                    end

                default: e_csrData = 32'h0;
            endcase
        end

    always @(*)
        begin
            //Branch decision logic 
            case(e_funct3)
                3'b000: e_takeBranch = e_isEQ;
                3'b001: e_takeBranch = !e_isEQ;
                3'b100: e_takeBranch = e_isLT;
                3'b101: e_takeBranch = !e_isLT;
                3'b110: e_takeBranch = e_isLTU;
                3'b111: e_takeBranch = !e_isLTU;

                default:
                    e_takeBranch = 0;
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

                    f_pc <= RESET_ADDRESS; fd_pc <= 0; de_pc <= 0;
                    f_addrRead <=  RESET_ADDRESS;
                    // f_kill_response <= 0;

                    de_pcPlusImm <= 0;

                    // fd_instr <= NOP; 
                    de_instr <= NOP; em_instr <= NOP; mw_instr <= NOP; 

                    de_rs1 <= 0; de_rs2 <= 0;                    

                    de_loadAddr <= 0; em_loadAddr <= 0; mw_loadAddr <= 0;
                    de_storeAddr <= 0; em_storeAddr <= 0; mw_storeAddr <= 0;
                    em_dataWrite <= 0;

                    //f_addrRead <= 0; em_addrRead <= 0;
                    //f_readEnable <= 0; em_readEnable <= 0;  
                    // fd_nop <= 1;

                    em_rdId <= 0; mw_rdId <= 0;
                    em_funct3 <= 0; mw_funct3 <= 0;

                    em_isLoad <= 0; mw_isLoad <= 0;
                    em_isStore <= 0; mw_isStore <= 0;
                    em_isBranch <= 0; mw_isBranch <= 0;

                    // em_writeEnable <= 0;
                    // em_dataRead <= 0;
                    // em_addrWrite <= 0;
                    // em_dataWrite <= 0;
                    em_storeMask <= 0;

                    em_writeBackData <= 0; mw_writeBackData <= 0;
                    // em_writeBackEnable <= 0; mw_writeBackEnable <= 0;
                    f_readEnable <= 1;

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
                                f_addrRead <=  RESET_ADDRESS;
                                f_readEnable <= 1;
                                //f_addrRead <= RESET_ADDRESS;
                                fd_pc <= RESET_ADDRESS;
                                // de_pc <= RESET_ADDRESS;

                                // f_readEnable <= 1; 

                                state <= RUN;
                            end
                        RUN:
                            begin
                                f_readEnable <= !stallFetch;
                                //Schedule readEnable to go down at posedge of next clock cycle
                                //f_readEnable <= 0;

                                // if (controlHazard)
                                //     f_kill_response <= 1'b1;
                                // else if (f_readEnable)
                                //     f_kill_response <= 1'b0;

                                // if (f_readEnable && f_kill_response) begin
                                //     $display(
                                //         "FD_KILL cyc=%0d | f_pc=%h fd_pc=%h d_instr=%h flushD=%b ctrl=%b",
                                //         cycles, f_pc, fd_pc, d_instr, flushDecode, controlHazard
                                //     );
                                // end

                                //Calculate Branch, JAL and AUIPC targets here
                                //PC value + immediate based on isTYPE flags
                                // if (!stallFetch && !em_readEnable)
                                //     begin
                                //         fd_instr <= d_instr;
                                //         fd_pc <= f_pc;
                                //         fd_nop <= flushDecode;
                                //     end
                                // else
                                //     begin
                                //         fd_nop <= fd_nop;
                                //         fd_instr <= fd_instr;
                                //         fd_pc <= fd_pc;
                                //     end

                                // if (f_readEnable)
                                //     begin
                                //         //fd_nop <= 0;
                                //         //fd_instr <= (fd_nop) ? NOP : d_instr;
                                //         // fd_instr <= d_instr;
                                //         fd_instr <= flushDecode ? NOP : d_instr;
                                //         //fd_nextPc <= f_pcPlus4;
                                //         fd_pc <= f_pc;
                                //         fd_nop <= flushDecode;
                                //     end
                                // else
                                //     begin
                                //         //f_pc <= f_pcPlus4;
                                //         fd_nop <= fd_nop;
                                //         fd_instr <= fd_instr;
                                //         //fd_nextPc <= f_pcPlus4;
                                //         fd_pc <= fd_pc;
                                //     end

                                if (flushDecode)
                                    begin
                                        //fd_instr <= NOP;
                                        fd_pc <= fd_pc;
                                        // fd_nop <= 1'b1;
                                        // f_prev_pc <= f_pc;
                                    end
                                // else if (stallDecode)
                                //     begin
                                //         fd_instr <= fd_instr;
                                //         fd_pc <= fd_pc;
                                //         fd_nop <= fd_nop;
                                //     end
                                //else if (f_readEnable && !f_kill_response)
                                // else if (!stallFetch)
                                else if (f_readEnable)
                                    begin
                                        f_pc <= f_nextPc;
                                        f_addrRead <= f_nextPc;
                                        // fd_instr <= d_instr;
                                        // f_prev_pc <= f_pc;
                                        fd_pc <= f_pc;
                                        // fd_nop <= 0;
                                    end
                                else
                                    begin
                                        // fd_nop <= 1;
                                        //fd_instr <= NOP;
                                        fd_pc <= fd_pc;
                                        // f_prev_pc <= f_pc;
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

                                 if (controlHazard)
                                    begin
                                         if (f_readEnable && !em_readEnable)
                                            begin
                                                f_pc <= f_nextPc + 4;
                                            end
                                        else
                                            begin
                                                f_pc <= f_nextPc;
                                            end
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
// always_ff @(posedge clock) begin
    //     if (!reset && state == RUN) begin
    //         if (mw_isLoad && mw_rdId != 0 && mw_loadAddr >= 32'h81e0 && mw_loadAddr <= 32'h81f0) begin
    //             $display("LSU_WB cyc=%0d | mw_loadAddr=%h mw_funct3=%b dataRead=%h w_loadData=%h mw_rdId=x%0d de_pc=%h",
    //                 cycles,
    //                 mw_loadAddr,
    //                 mw_funct3,
    //                 dataRead,
    //                 w_loadData,
    //                 mw_rdId,
    //                 de_pc
    //             );
    //         end
    //     end
    // end

    // always_ff @(posedge clock) begin
    //     if (!reset && state == RUN) begin
    //         if (!stallDecode && !flushExecute && d_isLoad && fd_pc >= 32'h816c) begin
    //             $display("LOAD_DECODE cyc=%0d | fd_pc=%h rs1=x%0d rs1val=%h imm=%h computed_addr=%h | e_rd=x%0d em_rd=x%0d mw_rd=x%0d | dataHaz=%b rs1Conflict=%b",
    //                 cycles,
    //                 fd_pc,
    //                 d_rs1Id,
    //                 registerFile[d_rs1Id],
    //                 d_Iimm,
    //                 registerFile[d_rs1Id] + d_Iimm,
    //                 e_rdId,
    //                 em_rdId,
    //                 mw_rdId,
    //                 dataHazard,
    //                 rs1Conflict
    //             );
    //         end
    //     end
    // end
    
    // always_ff @(posedge clock) begin
    //     if (!reset && state == RUN) begin
    //         if (mem_resp_state == LOAD && de_pc >= 32'h816c) begin
    //             $display("MEM cyc=%0d type=LOAD addr=%h data=%h pc=%h",
    //                 cycles,
    //                 em_loadAddr,
    //                 dataRead,
    //                 de_pc
    //             );
    //         end
    //     end
    // end

    // always_ff @(posedge clock) begin
    //     if (!reset && state == RUN) begin
    //         if (f_readEnable) begin
    //             $display(
    //                 "FETCH_REQ cyc=%0d f_addrRead=%h controlHaz=%b stallF=%b preFull=%b",
    //                 cycles,
    //                 f_addrRead,
    //                 controlHazard,
    //                 stallFetch,
    //                 prefetchFull
    //             );
    //         end
    //     end
    // end

    // always_ff @(posedge clock) begin
    //     if (!reset && state == RUN) begin
    //         if (prefetchWriteEnable) begin
    //             $display(
    //                 "MEM_RESP cyc=%0d f_addrRead=%h data=%h writeEnable=%b",
    //                 cycles,
    //                 f_addrRead,
    //                 dataRead,
    //                 prefetchWriteEnable
    //             );
    //         end
    //     end
    // end

    // always_ff @(posedge clock) begin
    //     if (!reset && state == RUN) begin
    //         if (prefetchWriteEnable) begin
    //             $display(
    //                 "FIFO_PUSH cyc=%0d pc=%h instr=%h (memResp=%h) FULL=%b",
    //                 cycles,
    //                 prefetchDataWrite[63:32],
    //                 prefetchDataWrite[31:0],
    //                 f_addrRead,
    //                 prefetchFull
    //             );
    //         end
    //     end
    // end

    // always_ff @(posedge clock) begin
    //     if (!reset && state == RUN) begin
    //         if (prefetchReadEnable) begin
    //             $display(
    //                 "FIFO_POP cyc=%0d pc=%h instr=%h valid=%b stallD=%b flushD=%b",
    //                 cycles,
    //                 prefetchDataRead[63:32],
    //                 prefetchDataRead[31:0],
    //                 decodeIsValid,
    //                 stallDecode,
    //                 flushDecode
    //             );
    //         end
    //     end
    // end

    // always_ff @(posedge clock) begin
    //     if (!reset && state == RUN) begin
    //         if (decodeIsValid) begin
    //             $display(
    //                 "DECODE cyc=%0d fd_pc=%h fd_instr=%h de_pc=%h de_instr=%h stallD=%b flushD=%b",
    //                 cycles,
    //                 fd_pc,
    //                 fd_instr,
    //                 de_pc,
    //                 de_instr,
    //                 stallDecode,
    //                 flushDecode
    //             );
    //         end
    //     end
    // end

    // `ifdef SIMULATION
    //     always @(posedge clock) 
    //         begin
    //             $display("PC=%0d instr=%h", f_pc, d_instr);
    //             $display("Instruction opcode %b", dataRead[6:0]);
                
    //             case (1'b1)
    //                 d_isALUreg: $display("ALUreg rd=%0d rs1=%0d rs2=%0d funct3=%b", d_rdId, d_rs1Id, d_rs2Id, d_funct3);
    //                 d_isALUimm: $display("ALUimm rd=%0d rs1=%0d imm=%0d funct3=%b", d_rdId, d_rs1Id, d_Iimm, d_funct3);
    //                 d_isLoad:   $display("LOAD");
    //                 d_isStore:  $display("STORE");
    //                 d_isBranch: $display("BRANCH");
    //                 d_isJAL:    $display("JAL");
    //                 d_isJALR:   $display("JALR");
    //                 d_isLUI:    $display("LUI");
    //                 d_isAUIPC:  $display("AUIPC");
    //                 d_isSYSTEM: $display("SYSTEM (EBREAK)");
    //             endcase
    //         end
    // `endif

// `ifdef SIMULATION
// always_ff @(posedge clock) begin
//     if (!reset && state == RUN) begin
//         if (f_readEnable && !f_kill_response && !flushDecode && !stallDecode && !em_readEnable && !em_writeEnable) begin
//             $display(
//                 "FD_ACCEPT cyc=%0d | fd_accept=1 | fRE=%b f_pc=%h f_prev_pc=%h d_instr=%h -> fd_pc_next=%h | stallF=%b stallD=%b emRE=%b emWE=%b flushD=%b",
//                 cycles,
//                 f_readEnable,
//                 f_pc,
//                 f_prev_pc,
//                 d_instr,
//                 f_prev_pc,
//                 stallFetch,
//                 stallDecode,
//                 em_readEnable,
//                 em_writeEnable,
//                 flushDecode
//             );
//         end
//     end
// end
// `endif
// `ifdef SIMULATION
// always_ff @(posedge clock) begin
//     if (!reset && state == RUN) begin
//         if (em_isLoad || mw_isLoad || em_isStore || mw_isStore) begin
//             $display(
//                 "MEM_CHECK cyc=%0d | EM instr=%h load=%b store=%b loadAddr=%h storeAddr=%h dataWrite=%h mask=%b | MW instr=%h load=%b store=%b loadAddr=%h storeAddr=%h | dataRead=%h w_loadData=%h | x5=%h x6=%h x7=%h x28=%h",
//                 cycles,
//                 em_instr, em_isLoad, em_isStore, em_loadAddr, em_storeAddr, em_dataWrite, em_storeMask,
//                 mw_instr, mw_isLoad, mw_isStore, mw_loadAddr, mw_storeAddr,
//                 dataRead, w_loadData,
//                 registerFile[5], registerFile[6], registerFile[7], registerFile[28]
//             );
//         end
//     end
// end
// `endif

// `ifdef SIMULATION
// always_ff @(posedge clock) begin
//     if (!reset && state == RUN) begin
//         if (fd_pc >= 32'h8048 && fd_pc <= 32'h8060) begin
//             $display(
//                 "LOOP_TRACE cyc=%0d | FD pc=%h instr=%h | DE pc=%h instr=%h | x5=%h x6=%h x7=%h x28=%h | stallF=%b stallD=%b flushD=%b flushE=%b",
//                 cycles,
//                 fd_pc, fd_instr,
//                 de_pc, de_instr,
//                 registerFile[5],
//                 registerFile[6],
//                 registerFile[7],
//                 registerFile[28],
//                 stallFetch,
//                 stallDecode,
//                 flushDecode,
//                 flushExecute
//             );
//         end
//     end
// end
// `endif

// `ifdef SIMULATION
// always_ff @(posedge clock) begin
//     if (!reset && state == RUN) begin
//         if (de_instr == 32'h00000317 ||  // auipc x6, 0
//             de_instr == 32'h1d830313 ||  // addi x6,x6,0x1d8
//             de_instr == 32'h1b430313 ||  // addi x6,x6,0x1b4
//             de_instr == 32'h00130313 ||  // addi x6,x6,1
//             mw_rdId == 5'd6) begin
//             $display(
//                 "X6_TRACE cyc=%0d | DE pc=%h instr=%h rs1=%0d rd=%0d de_rs1=%h imm=%h aluOut=%h de_pcPlusImm=%h | EM instr=%h rd=%0d wbData=%h | MW instr=%h rd=%0d wbData=%h wbEn=%b | x6=%h",
//                 cycles,
//                 de_pc, de_instr, e_rs1Id, e_rdId, de_rs1, e_Iimm, e_aluOut, de_pcPlusImm,
//                 em_instr, em_rdId, em_writeBackData,
//                 mw_instr, mw_rdId, mw_writeBackData, writeBackEnable,
//                 registerFile[6]
//             );
//         end
//     end
// end
// `endif


// `ifdef SIMULATION
// logic watching_x6_auipc;
// logic seen_x6_addi_waiting;
// logic [31:0] watched_auipc_pc;
// logic [31:0] expected_x6_base;
// logic [31:0] expected_x6_final;
// logic [31:0] watched_addi_pc;
// logic [31:0] watched_addi_instr;

// always_ff @(posedge clock) begin
//     if (reset) begin
//         watching_x6_auipc    <= 1'b0;
//         seen_x6_addi_waiting <= 1'b0;
//         watched_auipc_pc     <= 32'd0;
//         expected_x6_base     <= 32'd0;
//         expected_x6_final    <= 32'd0;
//         watched_addi_pc      <= 32'd0;
//         watched_addi_instr   <= NOP;
//     end
//     else if (state == RUN) begin

//         // ------------------------------------------------------------
//         // 1. AUIPC x6 enters DE
//         //    opcode AUIPC = 0010111, rd = x6
//         // ------------------------------------------------------------
//         if (de_instr[6:0] == 7'b0010111 && e_rdId == 5'd6) begin
//             watching_x6_auipc    <= 1'b1;
//             seen_x6_addi_waiting <= 1'b0;
//             watched_auipc_pc     <= de_pc;
//             expected_x6_base     <= de_pcPlusImm;

//             $display(
//                 "X6_SEQ_AUIPC_DE cyc=%0d | DE pc=%h instr=%h rd=x%0d de_pcPlusImm=%h | FD pc=%h instr=%h | x6_now=%h stallD=%b flushE=%b",
//                 cycles,
//                 de_pc,
//                 de_instr,
//                 e_rdId,
//                 de_pcPlusImm,
//                 fd_pc,
//                 fd_instr,
//                 registerFile[6],
//                 stallDecode,
//                 flushExecute
//             );
//         end

//         // ------------------------------------------------------------
//         // 2. Dependent ADDI x6,x6,imm waits in FD while x6 unresolved
//         //    opcode OP-IMM = 0010011, rd=x6, rs1=x6
//         // ------------------------------------------------------------
//         if (watching_x6_auipc &&
//             fd_instr[6:0] == 7'b0010011 &&
//             d_rdId == 5'd6 &&
//             d_rs1Id == 5'd6) begin

//             seen_x6_addi_waiting <= 1'b1;
//             watched_addi_pc      <= fd_pc;
//             watched_addi_instr   <= fd_instr;
//             expected_x6_final    <= expected_x6_base + d_Iimm;

//             $display(
//                 "X6_SEQ_ADDI_IN_FD cyc=%0d | FD pc=%h instr=%h rs1=x%0d rd=x%0d imm=%h | expected_base=%h expected_final=%h | dataHaz=%b rs1C=%b rs2C=%b stallF=%b stallD=%b flushE=%b | DE pc=%h instr=%h | EM rd=x%0d MW rd=x%0d x6_now=%h",
//                 cycles,
//                 fd_pc,
//                 fd_instr,
//                 d_rs1Id,
//                 d_rdId,
//                 d_Iimm,
//                 expected_x6_base,
//                 expected_x6_base + d_Iimm,
//                 dataHazard,
//                 rs1Conflict,
//                 rs2Conflict,
//                 stallFetch,
//                 stallDecode,
//                 flushExecute,
//                 de_pc,
//                 de_instr,
//                 em_rdId,
//                 mw_rdId,
//                 registerFile[6]
//             );
//         end

//         // ------------------------------------------------------------
//         // 3. AUIPC reaches MW/writeback path
//         // ------------------------------------------------------------
//         if (watching_x6_auipc &&
//             mw_instr[6:0] == 7'b0010111 &&
//             mw_rdId == 5'd6) begin

//             $display(
//                 "X6_SEQ_AUIPC_WB cyc=%0d | MW pc? instr=%h rd=x%0d wbData=%h wbEn=%b | expected_base=%h | x6_before_write=%h | FD pc=%h instr=%h | DE pc=%h instr=%h",
//                 cycles,
//                 mw_instr,
//                 mw_rdId,
//                 mw_writeBackData,
//                 writeBackEnable,
//                 expected_x6_base,
//                 registerFile[6],
//                 fd_pc,
//                 fd_instr,
//                 de_pc,
//                 de_instr
//             );
//         end

//         // ------------------------------------------------------------
//         // 4. Dependent ADDI finally enters DE
//         // ------------------------------------------------------------
//         if (watching_x6_auipc &&
//             de_instr[6:0] == 7'b0010011 &&
//             e_rdId == 5'd6 &&
//             e_rs1Id == 5'd6) begin

//             $display(
//                 "X6_SEQ_ADDI_DE cyc=%0d | DE pc=%h instr=%h rs1=x%0d rd=x%0d de_rs1=%h imm=%h aluOut=%h | expected_base=%h expected_final=%h | x6_reg_now=%h | %s",
//                 cycles,
//                 de_pc,
//                 de_instr,
//                 e_rs1Id,
//                 e_rdId,
//                 de_rs1,
//                 e_Iimm,
//                 e_aluOut,
//                 expected_x6_base,
//                 expected_x6_final,
//                 registerFile[6],
//                 (de_rs1 == expected_x6_base) ? "OK_BASE" : "BAD_BASE"
//             );
//         end

//         // ------------------------------------------------------------
//         // 5. ADDI writes final x6
//         // ------------------------------------------------------------
//         if (watching_x6_auipc &&
//             seen_x6_addi_waiting &&
//             mw_instr[6:0] == 7'b0010011 &&
//             mw_rdId == 5'd6) begin

//             $display(
//                 "X6_SEQ_ADDI_WB cyc=%0d | MW instr=%h rd=x%0d wbData=%h wbEn=%b | expected_final=%h | x6_before_write=%h | %s",
//                 cycles,
//                 mw_instr,
//                 mw_rdId,
//                 mw_writeBackData,
//                 writeBackEnable,
//                 expected_x6_final,
//                 registerFile[6],
//                 (mw_writeBackData == expected_x6_final) ? "OK_FINAL" : "BAD_FINAL"
//             );

//             // End this watch window after the dependent ADDI reaches WB.
//             watching_x6_auipc    <= 1'b0;
//             seen_x6_addi_waiting <= 1'b0;
//         end

//         // ------------------------------------------------------------
//         // Failure detector:
//         // AUIPC seen, but the dependent ADDI disappeared.
//         // ------------------------------------------------------------
//         if (watching_x6_auipc &&
//             !seen_x6_addi_waiting &&
//             fd_pc > watched_auipc_pc + 32'd8 &&
//             de_pc > watched_auipc_pc + 32'd8) begin

//             $display(
//                 "X6_SEQ_MISSING_ADDI cyc=%0d | watched AUIPC pc=%h expected next ADDI pc=%h | FD pc=%h instr=%h | DE pc=%h instr=%h | f_pc=%h f_prev=%h d_instr=%h | stallF=%b stallD=%b flushD=%b flushE=%b dataHaz=%b rs1C=%b rs2C=%b | x6=%h",
//                 cycles,
//                 watched_auipc_pc,
//                 watched_auipc_pc + 32'd4,
//                 fd_pc,
//                 fd_instr,
//                 de_pc,
//                 de_instr,
//                 f_pc,
//                 f_prev_pc,
//                 d_instr,
//                 stallFetch,
//                 stallDecode,
//                 flushDecode,
//                 flushExecute,
//                 dataHazard,
//                 rs1Conflict,
//                 rs2Conflict,
//                 registerFile[6]
//             );
//         end
//     end
// end
// `endif

// `ifdef SIMULATION
// always_ff @(posedge clock) begin
//     if (!reset && cycles < 40) begin
//         $display(
//             "HEARTBEAT cyc=%0d state=%0d | F pc=%h f_prev=%h fRE=%b d_instr=%h | FD pc=%h instr=%h nop=%b | DE pc=%h instr=%h | stallF=%b stallD=%b flushD=%b flushE=%b dataHaz=%b rs1C=%b rs2C=%b | e_rd=%0d em_rd=%0d mw_rd=%0d | x6=%h",
//             cycles,
//             state,
//             f_pc,
//             f_prev_pc,
//             f_readEnable,
//             d_instr,
//             fd_pc,
//             fd_instr,
//             fd_nop,
//             de_pc,
//             de_instr,
//             stallFetch,
//             stallDecode,
//             flushDecode,
//             flushExecute,
//             dataHazard,
//             rs1Conflict,
//             rs2Conflict,
//             e_rdId,
//             em_rdId,
//             mw_rdId,
//             registerFile[6]
//         );
//     end
// end
// `endif

// `ifdef SIMULATION
// always_ff @(posedge clock) begin
//     if (!reset && state == RUN) begin
//         if (de_instr[6:0] == 7'b1100011) begin
//             $display(
//                 "BRANCH_OPERANDS cyc=%0d | DE pc=%h instr=%h funct3=%b take=%b target=%h | rs1Id=%0d rs2Id=%0d de_rs1=%h de_rs2=%h | x5=%h x28=%h | stallF=%b stallD=%b flushD=%b flushE=%b dataHaz=%b rs1C=%b rs2C=%b | e_rd=%0d em_rd=%0d mw_rd=%0d",
//                 cycles,
//                 de_pc,
//                 de_instr,
//                 e_funct3,
//                 e_takeBranch,
//                 de_pcPlusImm,
//                 e_rs1Id,
//                 e_rs2Id,
//                 de_rs1,
//                 de_rs2,
//                 registerFile[5],
//                 registerFile[28],
//                 stallFetch,
//                 stallDecode,
//                 flushDecode,
//                 flushExecute,
//                 dataHazard,
//                 rs1Conflict,
//                 rs2Conflict,
//                 e_rdId,
//                 em_rdId,
//                 mw_rdId
//             );
//         end
//     end
// end
// `endif

// `ifdef SIMULATION
// always_ff @(posedge clock) begin
//     if (!reset && state == RUN) begin

//         // Any unknown on the shared memory interface
//         if ($isunknown(dataRead) || $isunknown(addrRead) || $isunknown(readEnable) ||
//             $isunknown(writeEnable) || $isunknown(addrWrite) || $isunknown(dataWrite)) begin
//             $display(
//                 "X_MEM_IF cyc=%0d | readEn=%b addrRead=%h dataRead=%h | writeEn=%b addrWrite=%h dataWrite=%h mask=%b | f_pc=%h f_prev=%h fRE=%b emRE=%b emWE=%b",
//                 cycles,
//                 readEnable,
//                 addrRead,
//                 dataRead,
//                 writeEnable,
//                 addrWrite,
//                 dataWrite,
//                 bramWriteMask,
//                 f_pc,
//                 f_prev_pc,
//                 f_readEnable,
//                 em_readEnable,
//                 em_writeEnable
//             );
//         end

//         // Any unknown produced by load path
//         if (mw_isLoad && mw_rdId != 0 &&
//             ($isunknown(w_loadData) || $isunknown(dataRead) || $isunknown(mw_loadAddr))) begin
//             $display(
//                 "X_LOAD_WB cyc=%0d | MW instr=%h rd=x%0d loadAddr=%h funct3=%b dataRead=%h w_loadData=%h | addrRead=%h readEn=%b | f_pc=%h fd_pc=%h de_pc=%h",
//                 cycles,
//                 mw_instr,
//                 mw_rdId,
//                 mw_loadAddr,
//                 mw_funct3,
//                 dataRead,
//                 w_loadData,
//                 addrRead,
//                 readEnable,
//                 f_pc,
//                 fd_pc,
//                 de_pc
//             );
//         end

//         // Specifically catch x14 getting written
//         if ((mw_isLoad && mw_rdId == 5'd14) ||
//             (writeBackEnable && mw_rdId == 5'd14)) begin
//             $display(
//                 "X14_WRITE cyc=%0d | isLoad=%b wbEn=%b MW instr=%h rd=x%0d wbData=%h loadData=%h dataRead=%h loadAddr=%h | x14_before=%h | unknownLoad=%b unknownWB=%b",
//                 cycles,
//                 mw_isLoad,
//                 writeBackEnable,
//                 mw_instr,
//                 mw_rdId,
//                 mw_writeBackData,
//                 w_loadData,
//                 dataRead,
//                 mw_loadAddr,
//                 registerFile[14],
//                 $isunknown(w_loadData),
//                 $isunknown(mw_writeBackData)
//             );
//         end

//         // Catch the first moment x14 is already poisoned
//         if ($isunknown(registerFile[14])) begin
//             $display(
//                 "X14_POISONED cyc=%0d | x14=%h | FD pc=%h instr=%h | DE pc=%h instr=%h | EM instr=%h rd=x%0d | MW instr=%h rd=x%0d | dataRead=%h addrRead=%h",
//                 cycles,
//                 registerFile[14],
//                 fd_pc,
//                 fd_instr,
//                 de_pc,
//                 de_instr,
//                 em_instr,
//                 em_rdId,
//                 mw_instr,
//                 mw_rdId,
//                 dataRead,
//                 addrRead
//             );
//         end
//     end
// end
// `endif

// `ifdef SIMULATION
// always_ff @(posedge clock) begin
//     if (!reset && state == RUN) begin
//         if (f_pc >= 32'h00008200 || $isunknown(f_pc) || $isunknown(fd_instr) || $isunknown(de_instr)) begin
//             $display(
//                 "PC_ESCAPE cyc=%0d | f_pc=%h f_prev=%h fRE=%b readEn=%b addrRead=%h dataRead=%h | FD pc=%h instr=%h nop=%b | DE pc=%h instr=%h | rawCtrl=%b ctrl=%b take=%b target=%h jal=%b jalr=%b branch=%b | stallF=%b stallD=%b dataHaz=%b structHaz=%b",
//                 cycles,
//                 f_pc,
//                 f_prev_pc,
//                 f_readEnable,
//                 readEnable,
//                 addrRead,
//                 dataRead,
//                 fd_pc,
//                 fd_instr,
//                 fd_nop,
//                 de_pc,
//                 de_instr,
//                 rawControlHazard,
//                 controlHazard,
//                 e_takeBranch,
//                 de_pcPlusImm,
//                 e_isJAL,
//                 e_isJALR,
//                 e_isBranch,
//                 stallFetch,
//                 stallDecode,
//                 dataHazard,
//                 structuralHazard
//             );
//         end
//     end
// end
// `endif

endmodule