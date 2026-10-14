import cpu_types_pkg::*;

module csr #(
    parameter CLOCK_FREQ = 25000000
) (
    input logic clock,
    input logic reset,
    input logic retired,

    input logic [31:0] dataIn,
    input logic [11:0] address,
    input logic [1:0] op,
    input logic readEnable,

    input logic trapTaken,
    input logic [31:0] trapCause,
    input logic [31:0] trapValue,
    input logic [31:0] trapPC,
    input logic isMRET,
    input logic isSRET,
    input logic [63:0] mtime,

    output logic [31:0] dataOut,
    output logic [31:0] trapTargetPC,
    output logic [31:0] mretTargetPC,
    output logic [31:0] sretTargetPC,
    output logic [31:0] mstatusOut,
    output logic [31:0] mieOut,
    output logic [31:0] mipOut,
    output logic [31:0] midelegOut,
    output logic [31:0] satpOut,
    output mode_t mode,

    output logic [PMP_ADDR_REG - 1:0][31:0] pmpAddr,
    output logic [PMP_CFG_REG - 1:0][31:0] pmpCfg,
    output logic csrIllegalAccess
);
    //Machine Trap Setup REGisters implemented - all 9
    //0x300-0x306 & 0x310 & 0x312
    localparam MTS_REG = 9;
    
    //Bitmasks for MTS registers:

    localparam BM_MSTATUS = 32'h807E79EA;
    localparam BM_MISA = 32'h00000000; //not writable in M mode
    localparam BM_MEDELEG = 32'h0000B3FF;
    localparam BM_MIDELEG = 32'h00000222;
    localparam BM_MIE = 32'h00000AAA;
    localparam BM_MTVEC = 32'hFFFFFFFD; //almost full write, just account for mode in 2 LSBs
    localparam BM_MCOUNTEREN = 32'h00000007;
    localparam BM_MSTATUSH = 32'h000006F0;
    localparam BM_MEDELEGH = 32'h00000000; //not writable in M mode for now

    //Machine Trap Handling REGisters implemented - first 5
    //0x340-0x344
    localparam MTH_REG = 5;

    //Bitmasks for MTH registers:

    localparam BM_MSCRATCH = 32'hFFFFFFFF; //full write to register, read by OS
    localparam BM_MEPC = 32'hFFFFFFFE;
    localparam BM_MCAUSE = 32'h8000BFFF;
    localparam BM_MTVAL = 32'hFFFFFFFF;
    localparam BM_MIP = 32'h00000AAA;

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
    //Only have physical register for 0x105 and 0x106
    localparam STS_REG = 2;

    localparam BM_SSTATUS = 32'h810C6162; //shadow
    localparam BM_SIE = 32'h00000222; //shadow
    localparam BM_STVEC = 32'hFFFFFFFD; //almost full write, just account for mode in 2 LSBs
    localparam BM_SCOUNTEREN = 32'h00000007;

    //Supervisor Trap Handling REGisters implemented - first 5
    //Only has physical storage for first 4
    //0x140-0x144
    localparam STH_REG = 4; //ovf not supported as of now

    localparam BM_SSCRATCH = 32'hFFFFFFFF; //full write to register, read by OS
    localparam BM_SEPC = 32'hFFFFFFFE;
    localparam BM_SCAUSE = 32'h8000BFFF;
    localparam BM_STVAL = 32'hFFFFFFFF;
    localparam BM_SIP = 32'h00000222; //shadow

    //Supervisor (Address) Protection and Translation - satp
    //0x180
    //dont need localparam for 1 register

    //however masking is different story
    localparam BM_SATP = 32'h803FFFFF; 

    //same thinking for Machine Counter Inhibited
    //0x320
    localparam BM_MCOUNTINHIBIT = 32'h00000005;

    //Supervisor Timer Compare REGisters to implement - all 2 TODO
    // localparam STC_REG = 2;

    //Unprivilaged Counter/Timers - cycles, time, instret and upper bit variants
    //0xC00 - 0xC02 & 0xC80 - 0xC82
    // localparam UCT_REG = 6;

    //Determines which physical register stores csr at 12 bit addr
    typedef enum logic [3:0] {
        STS,
        STH,
        SATP,
        MTS,
        MCI,
        MTH,
        PMP_CFG,
        PMP_ADDR,
        MCT,
        TIME,
        ILLEGAL_ACCESS
    } csr_t;

    csr_t csr_type;
    logic [6:0] index;

    logic [31:0] counter;

    //This register allows writes or not depending on what bits are set
    logic [31:0] bitmask;

    logic delegateTrap;

    logic [MTS_REG - 1:0][31:0] mts;
    logic [MTH_REG - 1:0][31:0] mth;
    logic [MCT_REG - 1:0][31:0] mct;
 
    logic [STS_REG - 1:0][31:0] sts;
    logic [STH_REG - 1:0][31:0] sth;
    logic [31:0] satp;
    logic [31:0] mcountinhibit;

    logic [31:0] tvec;
    logic cntDenied;
    logic satpTrapped;

    //Performs RW, RS, and RC operations of csr register
    function automatic [31:0] csrValue(input [31:0] csr);
        case (op)
            2'b01: csrValue = dataIn; //rw
            2'b10: csrValue = csr | dataIn; //rs
            2'b11: csrValue = csr & ~dataIn; //rc
            default: csrValue = csr;
        endcase
    endfunction

    //CSR address decoding
    always_comb
        begin
            if (address == 12'h100)
                begin
                    csr_type = MTS;
                    index = 0;
                    bitmask = BM_SSTATUS;
                end
            else if (address == 12'h104)
                begin
                    csr_type = MTS;
                    index = 4;
                    bitmask = BM_SIE;
                end
            else if (address == 12'h105)
                begin
                    csr_type = STS;
                    index = 0;
                    bitmask = BM_STVEC;
                end
            else if (address == 12'h106)
                begin
                    csr_type = STS;
                    index = 1;
                    bitmask = BM_SCOUNTEREN;
                end
            else if (address == 12'h140)
                begin
                    csr_type = STH;
                    index = 0;
                    bitmask = BM_SSCRATCH;
                end
            else if (address == 12'h141)
                begin
                    csr_type = STH;
                    index = 1;
                    bitmask = BM_SEPC;
                end
            else if (address == 12'h142)
                begin
                    csr_type = STH;
                    index = 2;
                    bitmask = BM_SCAUSE;
                end
            else if (address == 12'h143)
                begin
                    csr_type = STH;
                    index = 3;
                    bitmask = BM_STVAL;
                end
            else if (address == 12'h144)
                begin
                    csr_type = MTH;
                    index = 4;
                    bitmask = 32'h00000002;
                end
            else if (address == 12'h180)
                begin
                    csr_type = SATP;
                    bitmask = 0;
                    index = 0;
                end
            else if (address == 12'h300)
                begin
                    csr_type = MTS;
                    index = 0;
                    bitmask = BM_MSTATUS;
                end
            else if (address == 12'h301)
                begin
                    csr_type = MTS;
                    index = 1;
                    bitmask = BM_MISA;
                end
            else if (address == 12'h302)
                begin
                    csr_type = MTS;
                    index = 2;
                    bitmask = BM_MEDELEG;
                end
            else if (address == 12'h303)
                begin
                    csr_type = MTS;
                    index = 3;
                    bitmask = BM_MIDELEG;
                end
            else if (address == 12'h304)
                begin
                    csr_type = MTS;
                    index = 4;
                    bitmask = BM_MIE;
                end
            else if (address == 12'h305)
                begin
                    csr_type = MTS;
                    index = 5;
                    bitmask = BM_MTVEC;
                end
            else if (address == 12'h306)
                begin
                    csr_type = MTS;
                    index = 6;
                    bitmask = BM_MCOUNTEREN;
                end
            else if (address == 12'h310)
                begin
                    csr_type = MTS;
                    index = 7;
                    bitmask = BM_MSTATUSH;
                end
            else if (address == 12'h312)
                begin
                    csr_type = MTS;
                    index = 8;
                    bitmask = BM_MEDELEGH;
                end
            else if (address == 12'h320)
                begin
                    csr_type = MCI;
                    index = 0;
                    bitmask = BM_MCOUNTINHIBIT;
                end
            else if (address == 12'h340)
                begin
                    csr_type = MTH;
                    index = 0;
                    bitmask = BM_MSCRATCH;
                end
            else if (address == 12'h341)
                begin
                    csr_type = MTH;
                    index = 1;
                    bitmask = BM_MEPC;
                end
            else if (address == 12'h342)
                begin
                    csr_type = MTH;
                    index = 2;
                    bitmask = BM_MCAUSE;
                end
            else if (address == 12'h343)
                begin
                    csr_type = MTH;
                    index = 3;
                    bitmask = BM_MTVAL;
                end
            else if (address == 12'h344)
                begin
                    csr_type = MTH;
                    index = 4;
                    bitmask = BM_MIP;
                end
            else if (address >= 12'h3A0 && address <= 12'h3AF)
                begin
                    csr_type = PMP_CFG;
                    index = address[3:0];
                    bitmask = 0;
                end
            else if (address >= 12'h3B0 && address <= 12'h3EF)
                begin
                    csr_type = PMP_ADDR;
                    index = {address[5] ^ address[4], ~address[4], address[3:0]};
                    bitmask = 0;
                end
            else if ((address & 12'hF7D) == 12'hB00) //chooses 4 shadow mct regs
                begin
                    csr_type = MCT;
                    index = {address[7], address[1]};
                    bitmask = 32'hFFFFFFFF;
                end
            else if ((address & 12'hF7D) == 12'hC00) //chooses 4 shadow uct regs
                begin
                    csr_type = MCT;
                    index = {address[7], address[1]};
                    bitmask = 0;
                end
            else if (address == 12'hC01 || address == 12'hC81)
                begin
                    csr_type = TIME;
                    index = 0;
                    bitmask = 0;
                end
            else
                begin
                    csr_type = ILLEGAL_ACCESS;
                    index = 0;
                    bitmask = 32'h00000000;
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
                        STS: dataOut = sts[index] & bitmask;
                        STH: dataOut = sth[index] & bitmask;
                        SATP: dataOut = satp;
                        MCI: dataOut = mcountinhibit & bitmask;
                        MTS: dataOut = (address == 12'h301) ? mts[index] : (mts[index] & bitmask);
                        MTH: dataOut = (address == 12'h144) ? (mth[index] & BM_SIP) : (mth[index] & bitmask);
                        PMP_CFG: dataOut = pmpCfg[index];
                        PMP_ADDR: dataOut = pmpAddr[index];
                        MCT: dataOut = mct[index];
                        TIME: dataOut = address[7] ? mtime[63:32] : mtime[31:0];
                    endcase

                    if (csr_type == MTS && index == 0)
                        begin
                            dataOut[31] = (mts[0][14:13] == 2'b11) | (mts[0][16:15] == 2'b11) | (mts[0][10:9] == 2'b11);
                        end
                end
        end


    always_ff @(posedge clock) 
        begin
            if (reset) 
                begin
                    mts <= '0; 
                    mts[1] <= 32'h4014112D;
                    // mts[8] <= 32'h00000000;
                    mcountinhibit <= '0;
                    mth <= '0;
                    mct <= '0;

                    pmpCfg <= '0;
                    pmpAddr <= '0;

                    sts <= '0;
                    sth <= '0;
                    satp <='0;


                    counter <= 0;

                    mode <= MACHINE;
                end 
            else
                begin
                    //Increment mcycle unless inhibited
                    if (!mcountinhibit[0])
                        begin
                            {mct[2], mct[0]} <= {mct[2], mct[0]} + 64'd1;
                        end

                    //Increment minstret for retired instructions unless inhibited
                    if (retired && !mcountinhibit[2])
                        begin
                            {mct[3], mct[1]} <= {mct[3], mct[1]} + 64'd1;
                        end

                    if (trapTaken)
                        begin
                            // Delegate to S-mode only if:
                            //currently in S or U mode (M-mode traps never delegate down)
                            //the cause bit is set in medeleg (exceptions) or mideleg (interrupts)
                            // rapCause[31] = interrupt flag, trapCause[4:0] = cause code (0-31)
                            if (delegateTrap)
                                begin
                                    sth[1] <= trapPC; //sepc
                                    sth[2] <= trapCause; //scause
                                    sth[3] <= trapValue; //stval

                                    //sstatus is mts[0] bits: SIE=1, SPIE=5, SPP=8
                                    mts[0][5] <= mts[0][1]; //SPIE <= SIE
                                    mts[0][1] <= 1'b0; //disable S-mode interrupts
                                    mts[0][8] <= mode[0]; //SPP <= previous mode

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
                            mode <= mode_t'(mts[0][12:11]);;

                            //Restore interrupt enable
                            mts[0][3] <= mts[0][7];

                            //Set MPIE
                            mts[0][7] <= 1'b1;

                            //Clear MPP after returning
                            mts[0][12:11] <= 2'b00;

                            //clear out MPRV when cpu not in machine mode
                            if (mts[0][12:11] != 2'b11)
                                begin
                                    mts[0][17] <= 1'b0;
                                end
                    
                        end
                    else if (isSRET)
                        begin
                            mode <= mode_t'({1'b0, mts[0][8]});

                            //SIE <= SPIE
                            mts[0][1] <= mts[0][5];

                            //Set SPIE
                            mts[0][5] <= 1'b1;

                            //Clear SPP after return
                            mts[0][8] <= 1'b0;

                            //Clear MPRV for modes under Machine
                            mts[0][17] <= 1'b0;
                        end
                    else if ((op != 2'b00) && (csr_type != ILLEGAL_ACCESS) && !csrIllegalAccess)
                        begin
                            //Write port of CSRs
                            case (csr_type)
                                MCT: mct[index] <= (mct[index] & ~bitmask) | (csrValue(mct[index]) & bitmask);
                                STS: sts[index] <= (sts[index] & ~bitmask) | (csrValue(sts[index]) & bitmask);
                                STH: sth[index] <= (sth[index] & ~bitmask) | (csrValue(sth[index]) & bitmask);
                                SATP: satp <= csrValue(satp) & BM_SATP;
                                MTS: mts[index] <= (mts[index] & ~bitmask) | (csrValue(mts[index]) & bitmask);
                                MCI: mcountinhibit <= (mcountinhibit & ~bitmask) | (csrValue(mcountinhibit) & bitmask);
                                MTH: mth[index] <= (mth[index] & ~bitmask) | (csrValue(mth[index]) & bitmask);
                                PMP_CFG: pmpCfg[index] <= csrValue(pmpCfg[index]);
                                PMP_ADDR: pmpAddr[index] <= csrValue(pmpAddr[index]);
                            endcase
                        end
                end
        end

    assign satpTrapped = (csr_type == SATP) && (mode == SUPERVISOR) && mts[0][20];

    assign cntDenied = (address[11:8] == 4'hC) && (((mode != MACHINE) && !mts[6][address[1:0]]) || ((mode == USER) && !sts[1][address[1:0]]));

    assign delegateTrap = (mode != MACHINE) && (trapCause[31] ? mts[3][trapCause[4:0]] : mts[2][trapCause[4:0]]);

    assign tvec = delegateTrap ? sts[0] : mts[5];

    //DOES NOT TAKE INTO ACCOUNT VECTORED MODE FOR PC VALUES
    // assign trapTargetPC = delegateTrap ? sts[0] : mts[5]; // stvec : mtvec

    assign trapTargetPC = (tvec[0] && trapCause[31]) ?
                                ({tvec[31:2], 2'b00} + {trapCause[29:0], 2'b00})
                                                     : {tvec[31:2], 2'b00};

    assign mretTargetPC = mth[1]; //mepc
    assign sretTargetPC = sth[1]; //sepc

    assign csrIllegalAccess = (readEnable || (op != 2'b00)) && ((mode < address[9:8]) || (csr_type == ILLEGAL_ACCESS) || ((op != 2'b00) && (address[11:10] == 2'b11)) || cntDenied || satpTrapped);

    assign mstatusOut = mts[0] & BM_MSTATUS;
    assign mieOut = mts[4];
    assign mipOut = mth[4];
    assign midelegOut = mts[3];
    assign satpOut = satp;

    // mhartid (0xF14) doesn’t exist. OpenSBI reads it unconditionally at boot. Add mhartid=0, plus mvendorid, marchid, mimpid (0xF11–0xF13) and mconfigptr (0xF15) as read-only zeros.

endmodule
