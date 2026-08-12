import cpu_types_pkg::*;

module csr #(
    parameter CLOCK_FREQ = 25000000
) (
    input  logic clock,
    input  logic reset,
    input  logic retired,

    input  logic [31:0] dataIn,
    input  logic [11:0] address,
    input  logic [1:0] op,
    input  logic readEnable,

    input  logic trapTaken,
    input  logic [31:0] trapCause,
    input  logic [31:0] trapValue,
    input  logic [31:0] trapPC,
    input  logic isMRET,
    input  logic isSRET,

    output logic [31:0] dataOut,
    output logic [31:0] trapTargetPC,
    output logic [31:0] mretTargetPC,
    output logic [31:0] sretTargetPC,
    output mode_t mode,

    output logic [PMP_ADDR_REG - 1:0][31:0] pmpAddr,
    output logic [PMP_CFG_REG - 1:0][31:0] pmpCfg,
    output logic csrIllegalAccess
);
    //Machine Trap Setup REGisters implemented - all 9
    //0x300-0x306 & 0x310 & 0x312
    localparam MTS_REG = 9;

    //Machine Trap Handling REGisters implemented - first 5
    //0x340-0x344
    localparam MTH_REG = 5;

    //machine Physical Memory Protection REGisters implemented - all 16 and 64
    //0x3A0 - 0x3AF
    localparam PMP_CFG_REG = 16;

    //0x3B0 - 0x3EF
    localparam PMP_ADDR_REG = 64;

    //Machine Counter/Timers REGisters implemented - instret and cycles and upper bit variants
    //0xB00 & 0xB02 & 0xB80 & 0xB82
    localparam MCT_REG = 4;
    
    //Supervisor Trap Setup REGisters implemented - all 4
    //0x100 & 0x104 - 0x106
    localparam STS_REG = 4;

    //Supervisor Trap Handling REGisters implemented - first 5
    //0x140-0x144
    localparam SPT_REG = 5; //ovf not supported as of now

    //Supervisor (Address) Protection and Translation - satp
    //0x180
    //dont need localparam for 1 register

    //Supervisor Timer Compare REGisters to implement - all 2 TODO
    // localparam STC_REG = 2;

    //Unprivilaged Counter/Timers - cycles, time, instret and upper bit variants
    //0xC00 - 0xC02 & 0xC80 - 0xC82
    localparam UCT_REG = 6;

    typedef enum logic [3:0] {
        STS,
        SPT,
        SATP,
        MTS,       
        MTH,
        PMP_CFG,
        PMP_ADDR,
        MCT,
        UCT,
        ILLEGAL_ACCESS
    } csr_t;

    csr_t csr_type;
    logic [6:0] index;

    logic [31:0] counter;

    logic [1:0] csrPrivilageLevel;
    logic delegateTrap;

    logic [MTS_REG - 1:0][31:0] mts;
    logic [MTH_REG - 1:0][31:0] mth;
    logic [MCT_REG - 1:0][31:0] mct;
 
    logic [STS_REG - 1:0][31:0] sts;
    logic [SPT_REG - 1:0][31:0] spt;
    logic [31:0] satp;

    logic [UCT_REG - 1:0][31:0] uct;

    function automatic [31:0] csrValue(input [31:0] csr);
        case (op)
            2'b01: csrValue = dataIn;
            2'b10: csrValue = (dataIn != 0) ? (csr | dataIn) : csr;
            2'b11: csrValue = (dataIn != 0) ? (csr & ~dataIn) : csr;
            default: csrValue = csr;
        endcase
    endfunction

    always_comb
        begin
            index = '0;

            if (address == 12'h100)
                begin
                    csr_type = STS;
                    index = 0;
                end
            else if (address >= 12'h104 && address <= 12'h106)
                begin
                    csr_type = STS;
                    index = address - 12'h104 + 1;
                end
            else if (address >= 12'h140 && address <= 12'h144)
                begin
                    csr_type = SPT;
                    index = address - 12'h140;
                end
            else if (address == 12'h180)
                begin
                    csr_type = SATP;
                end
            else if (address >= 12'h300 && address <= 12'h306)
                begin
                    csr_type = MTS;
                    index = address - 12'h300;
                end
            else if (address == 12'h310)
                begin
                    csr_type = MTS;
                    index = 7;
                end
            else if (address == 12'h312)
                begin
                    csr_type = MTS;
                    index = 8;
                end
            else if (address >= 12'h340 && address <= 12'h344)
                begin
                    csr_type = MTH;
                    index = address - 12'h340;
                end
            else if (address >= 12'h3A0 && address <= 12'h3AF)
                begin
                    csr_type = PMP_CFG;
                    index = address - 12'h3A0;
                end
            else if (address >= 12'h3B0 && address <= 12'h3EF)
                begin
                    csr_type = PMP_ADDR;
                    index = address - 12'h3B0;
                end
            else if ((address >= 12'hC00 && address <= 12'hC02) ||
                    (address >= 12'hC80 && address <= 12'hC82))
                begin
                    csr_type = UCT;

                    if (!address[7])
                        begin
                            index = address[1:0];
                        end
                    else
                        begin
                            index = address[1:0] + 3;
                        end
                end
             else if ((address >= 12'hB00 && address <= 12'hB02) ||
                    (address >= 12'hB80 && address <= 12'hB82))
                begin
                    if (address[4:0] == 4'h1)
                        begin
                            csr_type = ILLEGAL_ACCESS;
                        end
                    else
                        begin
                            csr_type = MCT;
                            index = {address[7], address[1]};
                        end
                end
            else
                begin
                    csr_type = ILLEGAL_ACCESS;
                end
        end

    always_comb
        begin
            if (!readEnable)
                begin
                    dataOut = '0;
                end
            else
                begin
                    dataOut = '0;

                    case (csr_type)
                        STS: dataOut = sts[index];
                        SPT: dataOut = spt[index];
                        SATP: dataOut = satp;
                        MTS: dataOut = mts[index];
                        MTH: dataOut = mth[index];
                        PMP_CFG: dataOut = pmpCfg[index];
                        PMP_ADDR: dataOut = pmpAddr[index];
                        MCT: dataOut = mct[index];
                        UCT: dataOut = uct[index];
                    endcase
                end
        end

    always_ff @(posedge clock) 
        begin
            if (reset) 
                begin
                    mts <= '0; 
                    mth <= '0;
                    mct <= '0;

                    pmpCfg <= '0;
                    pmpAddr <= '0;

                    sts <= '0;
                    spt <= '0;
                    satp <='0;

                    uct <= '0;

                    mode <= MACHINE;
                end 
            else
                begin
                    if (uct[0] != 32'hFFFF_FFFF)
                        begin
                            uct[0] <= uct[0] + 1;
                        end
                    else
                        begin
                            uct[3] <= uct[3] + 1;
                        end

                    if (counter == CLOCK_FREQ - 1) 
                        begin
                            counter <= 0;
                            //Counts seconds elapsed after CPU reset
                            if (uct[1] != 32'hFFFF_FFFF)
                                begin
                                    uct[1] <= uct[1] + 1;
                                end
                            else
                                begin
                                    uct[4] <= uct[4] + 1;
                                end
                        end
                    else 
                        begin
                            counter <= counter + 1;
                        end

                    if (retired) 
                        begin
                            if (uct[2] != 32'hFFFF_FFFF)
                                begin
                                    uct[2] <= uct[2] + 1;
                                end
                            else
                                begin
                                    uct[5] <= uct[5] + 1;
                                end
                        end

                    if (trapTaken)
                        begin
                            // Delegate to S-mode only if:
                            //currently in S or U mode (M-mode traps never delegate down)
                            //the cause bit is set in medeleg (exceptions) or mideleg (interrupts)
                            // rapCause[31] = interrupt flag, trapCause[4:0] = cause code (0-31)
                            if (delegateTrap)
                                begin
                                    spt[1] <= trapPC; //sepc
                                    spt[2] <= trapCause; //scause
                                    spt[3] <= trapValue; //stval

                                    //sstatus is sts[0] bits: SIE=1, SPIE=5, SPP=8
                                    sts[0][5] <= sts[0][1]; //SPIE <= SIE
                                    sts[0][1] <= 1'b0; //disable S-mode interrupts
                                    sts[0][8] <= mode[0]; //SPP <= previous mode

                                    mode <= SUPERVISOR;
                                end
                            else
                                begin
                                    mth[1] <= trapPC; //mepc
                                    mth[2] <= trapCause; //mcause
                                    mth[3] <= trapValue; //mtval

                                    //mstatus is mts[0] bits: MIE=3, MPIE=7
                                    mts[0][7] <= mts[0][3]; //MPIE <= MIE
                                    mts[0][3] <= 1'b0; //disable M-mode interrupts
                                    mts[0][12:11] <= mode; //MPP <= previous mode

                                    mode <= MACHINE;
                                end
                        end
                    else if (isMRET)
                        begin
                            mode <= mts[0][12:11];

                            //Restore interrupt enable
                            mts[0][3] <= mts[0][7];

                            //Set MPIE
                            mts[0][7] <= 1'b1;

                            //Clear MPP after returning
                            mts[0][12:11] <= 2'b00;
                        end
                    else if (isSRET)
                        begin
                            mode <= mode_t'({1'b0, sts[0][8]});

                            //SIE <= SPIE
                            sts[0][1] <= sts[0][5];

                            //Set SPIE
                            sts[0][5] <= 1'b1;

                            //Clear SPP after return
                            sts[0][8] <= 1'b0;
                        end
                    else if ((op != 2'b00) && (csr_type != ILLEGAL_ACCESS))
                        begin
                            case (csr_type)
                                STS: sts[index] <= csrValue(sts[index]);
                                SPT: spt[index] <= csrValue(spt[index]);
                                SATP: satp <= csrValue(satp);
                                MTS: mts[index] <= csrValue(mts[index]);
                                MTH: mth[index] <= csrValue(mth[index]);
                                PMP_CFG: pmpCfg[index] <= csrValue(pmpCfg[index]);
                                PMP_ADDR: pmpAddr[index] <= csrValue(pmpAddr[index]);
                            endcase
                        end
                end
        end

    assign delegateTrap = (mode != MACHINE) && (trapCause[31] ? mts[3][trapCause[4:0]] : mts[2][trapCause[4:0]]);

    assign trapTargetPC = delegateTrap ? sts[2] : mts[5]; // stvec : mtvec
    assign mretTargetPC = mth[1]; //mepc
    assign sretTargetPC = spt[1]; //sepc

    assign csrPrivilageLevel = address[9:8];

    assign csrIllegalAccess = (readEnable || (op != 2'b00)) && (mode < csrPrivilageLevel);;

endmodule
