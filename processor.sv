module processor #(
    parameter INIT = ""
) (
    input logic clock,
    input logic reset
);
    logic [6:0] pc = 0;

    logic [31:0] data_out;
    logic [31:0] instr;
    logic read_enable = 0;

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

    logic [4:0] rs1Id;
    logic [4:0] rs2Id;
    logic [4:0] rdId;

    logic [2:0] funct3;
    logic [6:0] funct7;

    logic [31:0] Uimm;
    logic [31:0] Iimm;
    logic [31:0] Simm;
    logic [31:0] Bimm;
    logic [31:0] Jimm;

    logic [31:0] rs1;
    logic [31:0] rs2;

    logic [31:0] registerFile [31:0];

    logic [31:0] aluOut;
    logic [31:0] writeBackData;
    logic writeBackEn;

    localparam FETCH_INSTR = 0;
    localparam FETCH_REGS = 1;
    localparam EXECUTE = 2;

    logic [1:0] state = FETCH_INSTR;

    bram_sdp #(
        .WIDTH(32), 
        .DEPTH(128),
        .INIT("instructions.mem")
    ) bram_inst (
        .clock_write(1'b0),
        .clock_read(clock),
        .write_enable(1'b0),
        .read_enable(read_enable),
        .addr_write(7'b0000000),
        .addr_read(pc),
        .data_in(0),
        .data_out
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
        .isALUreg,
        .instr,
        .funct3,
        .funct7,
        .Iimm,
        .aluOut
    );
   
    always_ff @(posedge clock) 
        begin
            if(!reset) 
                begin
                    pc    <= 0;
                    state <= FETCH_INSTR;
                end 
            else 
                begin
                    if(writeBackEn && rdId != 0) 
                        begin
                            registerFile[rdId] <= writeBackData;

                            // For displaying what happens.
                            //if(rdId == 1) begin
                            //    leds <= writeBackData;
                            //end
	                    end
                 end
            case(state)
                FETCH_INSTR: 
                    begin
                        instr <= data_out;
                        state <= FETCH_REGS;
                    end
                FETCH_REGS: 
                    begin
                        rs1 <= registerFile[rs1Id];
                        rs2 <= registerFile[rs2Id];
                        state <= EXECUTE;
                    end
                EXECUTE: 
                    begin
                        pc <= pc + 1;
                        state <= FETCH_INSTR;
                    end
            endcase
      end

    always_ff @(posedge clock, posedge reset) 
        begin
            if (reset)
                begin
                    read_enable <= 1;
                    pc <= 0;
                end
            else 
                begin
                    pc <= pc + 1;

                    if (pc == 73)
                        pc <= 0;
                end
        end 

    // register write back
    assign writeBackData = aluOut; 
    assign writeBackEn = (state == EXECUTE && (isALUreg || isALUimm));   

    `ifdef SIMULATION
        always @(posedge clock) 
            begin
                $display("PC=%0d instr=%h", pc, instr);
                $display("Instruction opcode %b", data_out[6:0]);
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