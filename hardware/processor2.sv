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

    //Instruction variable and its variants (bubbled)
    logic [31:0] d_instr, de_instr, em_instr, mw_instr;

    //Read (BRAM & UART operation) variables (bubbled)
    logic f_readEnable, em_readEnable;
    logic [ADDR_WIDTH - 1:0] f_addrRead, em_addrRead;

    //NOT USED
    logic [31:0] em_dataRead;

    //Write (BRAM & UART operation) variables (bubbled)
    logic em_writeEnable;
    logic [ADDR_WIDTH - 1:0] em_addrWrite;
    logic [31:0] em_dataWrite;

    //Boolean flags used by the decoder, processor, and alu
    logic d_isALUreg, e_isALUreg; 
    logic d_isALUimm, e_isALUimm;
    logic d_isBranch, e_isBranch;
    logic d_isJALR, e_isJALR;    
    logic d_isJAL, e_isJAL;    
    logic d_isAUIPC, e_isAUIPC;    
    logic d_isLUI, e_isLUI;    
    logic d_isLoad, e_isLoad, em_isLoad, mw_isLoad;  
    logic d_isStore, e_isStore, em_isStore;
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
    //################### IMPLEMENT #################################################
    logic d_isEBREAK, e_isEBREAK;
    logic d_isECALL, e_isECALL;
    logic d_isCSRRS, e_isCSRRS;
    //###############################################################################

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
    logic em_writeBackEnable, mw_writeBackEnable;

    //Computed memory address for loads and stores
    logic [31:0] w_loadAddr, de_loadAddr, em_loadAddr, mw_loadAddr;
    logic [31:0] e_storeAddr, de_storeAddr;

    //Word written to word addressed bram and the mask 
    logic [31:0] e_storeData;
    logic [3:0] e_storeMask, em_storeMask;

    //Word loaded to register using combinatorial logic
    logic [31:0] w_loadData;

    //CSR Registers
    logic [63:0] cycles;
    logic [63:0] instructionsRetired;

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
                        e_csrData = instructionsRetired[31:0];
                    end
                12'hc82:
                    begin
                        e_csrData = instructionsRetired[63:32];
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
                    instructionsRetired <= 0;

                    state <= INITIAL;
                end
            else 
                begin
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


                                state <= EXECUTE;
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

                                /////////////////////IMPLEMENT EBREAK 
                                
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
                                
                                state <= MEMORY;	          
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

                                instructionsRetired <= instructionsRetired + 1;

                                state <= FETCH;
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