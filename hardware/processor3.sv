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
    logic [31:0] fd_nextPc, de_nextPc, em_nextPc, mw_nextPc;
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
    logic [31:0] f_instr, fd_instr, de_instr, em_instr, mw_instr;

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
    assign d_effectiveInstr = (fd_nop) ? NOP : fd_instr;
    assign e_effectiveInstr = de_instr;
    //assign e_effectiveInstr = (flushExecute) ? NOP : de_instr;
    assign m_effectiveInstr = em_instr;
    assign w_effectiveInstr = mw_instr;
                  
    //Continously drive the target memory address (used by loads and stores)
    assign w_loadAddr = mw_loadAddr;
    assign e_storeAddr = de_storeAddr;
 
    //Continously drive the data read from BRAM 
    // assign memData = dataRead;
    assign f_instr = dataRead;

    // assign d_instr = instrPrefetched;
    // assign d_pc = pcPrefetched;

    //Continously drive the value of the pc for next instruction
    assign f_pcPlus4 = f_pc + 4;

    assign readEnable = (f_readEnable || em_readEnable) && !em_writeEnable;
    assign addrRead = em_readEnable ? em_addrRead : (f_readEnable ? f_addrRead : 0);

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

    assign rs1Conflict = d_readsRs1 && d_rs1Id != 0 && 
                        ((d_rs1Id == e_rdId && e_writesRd) || 
                         (d_rs1Id == em_rdId && m_writesRd) ||
                         (d_rs1Id == mw_rdId && w_writesRd));

    assign rs2Conflict = d_readsRs2 && d_rs2Id != 0 && 
                        ((d_rs2Id == e_rdId && e_writesRd) || 
                         (d_rs2Id == em_rdId && m_writesRd) ||
                         (d_rs2Id == mw_rdId && w_writesRd));

    //assign fd_nop = (fd_instr == NOP);

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

    assign em_readEnable = em_isLoad;
    assign em_writeEnable = em_isStore;

    //assign f_addrRead = f_pc;
    assign f_readEnable = !stallFetch;
    assign f_addrRead = (state == INITIAL) ? RESET_ADDRESS : f_pc;
    //assign f_readEnable = (state == INITIAL || state == RUN) && !stallFetch;

    // assign em_addrRead = de_loadAddr;
    // assign em_addrWrite <= de_storeAddr;
    // assign em_dataWrite <= e_storeData;
    // assign em_storeMask <= e_storeMask;

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

                    f_pc <= 0; fd_pc <= 0; de_pc <= 0;
                    fd_nextPc <= 0; de_nextPc <= 0; em_nextPc <= 0; mw_nextPc <= 0; 

                    de_pcPlusImm <= 0;

                    fd_instr <= NOP; de_instr <= NOP; em_instr <= NOP; mw_instr <= NOP; 

                    de_rs1 <= 0; de_rs2 <= 0;                    

                    de_loadAddr <= 0; em_loadAddr <= 0; mw_loadAddr <= 0;
                    de_storeAddr <= 0; em_storeAddr <= 0; mw_storeAddr <= 0;
                    em_dataWrite <= 0;

                    //f_addrRead <= 0; em_addrRead <= 0;
                    //f_readEnable <= 0; em_readEnable <= 0;  
                    fd_nop <= 1;

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
                                //f_addrRead <= RESET_ADDRESS;
                                // fd_pc <= RESET_ADDRESS;
                                // de_pc <= RESET_ADDRESS;

                                // f_readEnable <= 1; 

                                state <= RUN;
                            end
                        RUN:
                            begin
                                //Schedule readEnable to go down at posedge of next clock cycle
                                //f_readEnable <= 0;

                                //Calculate Branch, JAL and AUIPC targets here
                                //PC value + immediate based on isTYPE flags
                                if (!stallFetch && !em_readEnable)
                                    begin
                                        fd_instr <= f_instr;
                                        fd_pc <= f_pc;
                                        fd_nop <= flushDecode;
                                    end
                                else
                                    begin
                                        fd_nop <= fd_nop;
                                        fd_instr <= fd_instr;
                                        fd_pc <= fd_pc;
                                    end

                                // if (f_readEnable)
                                //     begin
                                
                                //         fd_instr <= f_instr;
                                //         fd_nextPc <= f_pcPlus4;
                                //         fd_pc <= f_pc;
                                //         fd_nop <= flushDecode;
                                //     end
                                // else
                                //     begin
                                //         //f_pc <= f_pcPlus4;
                                //         fd_nop <= fd_nop;
                                //         fd_instr <= fd_instr;
                                //         fd_nextPc <= f_pcPlus4;
                                //         fd_pc <= fd_pc;
                                //     end

                                if (!stallDecode)
                                    begin
                                        de_pc <= fd_pc;
                                        de_pcPlusImm <= fd_pc + (d_isJAL ? d_Jimm : (d_isAUIPC ? d_Uimm : d_Bimm));

                                        de_instr <= d_effectiveInstr;
                                        de_nextPc <= fd_nextPc;

                                        de_loadAddr <= registerFile[d_rs1Id] + d_Iimm;
                                        de_storeAddr <= registerFile[d_rs1Id] + d_Simm;

                                        de_rs1 <= registerFile[d_rs1Id];
                                        de_rs2 <= registerFile[d_rs2Id];
                                    end

                                //Compute values for the writeback and the next program counter

                                if ((e_isBranch && e_takeBranch) ||  e_isJAL)
                                    begin
                                        f_pc <= de_pcPlusImm;
                                    end
                                else if (e_isJALR)
                                    begin
                                        f_pc <= e_pcJALR;
                                    end
                                else
                                    begin
                                        f_pc <= f_pcPlus4;
                                    end
                                // else if (!stallFetch) begin
                                //     f_pc <= f_pcPlus4;
                                // end
                                // else begin
                                //     f_pc <= f_pc;
                                // end

                                // if (controlHazard)
                                //     begin
                                //         f_pc <= de_pcPlusImm;
                                //     end
                                // else if (!stallFetch)
                                //     begin
                                //         f_pc <= f_pcPlus4;
                                //     end
                                // else
                                //     begin
                                //         f_pc <= f_pc;
                                //     end

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
                                // if (e_isLoad) 
                                //     begin
                                //         em_readEnable <= 1;
                                //         em_addrRead <= de_loadAddr;
                                //     end
                                // else if (e_isStore) 
                                //     begin
                                //         em_addrWrite <= de_storeAddr;
                                //         em_dataWrite <= e_storeData;
                                //         em_storeMask <= e_storeMask;
                                //         em_writeEnable <= 1;
                                //     end

                                em_loadAddr <= de_loadAddr;
                                em_storeAddr <= de_storeAddr;
                                em_dataWrite <= e_storeData;
                                em_storeMask <= e_storeMask;

                                // if (e_isALUreg || e_isALUimm)
                                //     begin
                                //         if (e_effectiveInstr != NOP)
                                //             begin
                                //                 em_writeBackEnable <= 1;
                                //             end
                                //         else
                                //             begin
                                //                 em_writeBackEnable <= 0;
                                //             end
                                //     end
                                // else 
                                //     begin
                                //         em_writeBackEnable <= (e_isJAL ||
                                //                                e_isJALR ||
                                //                                e_isLUI ||
                                //                                e_isAUIPC ||
                                //                                e_isCSRRS);
                                //     end    

                                em_rdId <= e_rdId;
                                em_funct3 <= e_funct3;

                                em_isLoad <= e_isLoad;
                                em_isStore <= e_isStore;
                                em_isBranch <= e_isBranch;

                                // em_loadAddr <= de_loadAddr;
                                em_instr <= e_effectiveInstr;

                                //Schedule a writeback by driving writeBackEnable for one cycle
                                // mw_writeBackEnable <= em_writeBackEnable;

                                //Stop reading or writing at the WB state
                                if (em_isLoad)
                                    begin
                                        //em_readEnable <= 0;
                                        mw_loadAddr <= em_loadAddr;
                                    end
                                else if (em_isStore)
                                    begin
                                        //em_writeEnable <= 0;
                                        mw_storeAddr <= em_storeAddr;
                                    end

                                mw_rdId <= em_rdId;
                                mw_funct3 <= em_funct3;

                                mw_isLoad <= em_isLoad;
                                mw_loadAddr <= em_loadAddr;
                                mw_isBranch <= em_isBranch;

                                mw_nextPc <= em_nextPc;

                                mw_writeBackData <= em_writeBackData;

                                mw_instr <= m_effectiveInstr;

                                // if (em_readEnable)
                                //     begin
                                //         mw_memData <= dataRead;
                                //     end

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

                                //Make loads and stores visible in the writeback state
                                // mw_isStore <= em_isStore;
                                // mw_isBranch <= em_isBranch;

                                //Read next instruction
                                // f_pc <= mw_nextPc;
                                // f_addrRead <= mw_nextPc;
                                // f_readEnable <= 1;

                                //Stop writeback at next clock cycle
                                // mw_writeBackEnable <= 0;

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

endmodule