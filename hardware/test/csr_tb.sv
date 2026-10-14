`timescale 1ns/1ps
import cpu_types_pkg::*;

module csr_tb;

    logic clock, reset, retired;
    logic [31:0] dataIn;
    logic [11:0] address;
    logic [1:0] op;
    logic readEnable;

    logic trapTaken;
    logic [31:0] trapCause, trapValue, trapPC;
    logic isMRET, isSRET;
    logic [63:0] mtime;

    logic [31:0] dataOut;
    logic [31:0] trapTargetPC, mretTargetPC, sretTargetPC;

    // These outputs must be 32-bit in csr.sv as well.
    logic [31:0] mstatusOut, mieOut, mipOut, midelegOut, satpOut;

    mode_t mode;

    logic [63:0][31:0] pmpAddr;
    logic [15:0][31:0] pmpCfg;
    logic csrIllegalAccess;

    int errors = 0;

    logic [31:0] rd;

    csr dut (
        .clock(clock),
        .reset(reset),
        .retired(retired),

        .dataIn(dataIn),
        .address(address),
        .op(op),
        .readEnable(readEnable),

        .trapTaken(trapTaken),
        .trapCause(trapCause),
        .trapValue(trapValue),
        .trapPC(trapPC),
        .isMRET(isMRET),
        .isSRET(isSRET),
        .mtime(mtime),

        .dataOut(dataOut),
        .trapTargetPC(trapTargetPC),
        .mretTargetPC(mretTargetPC),
        .sretTargetPC(sretTargetPC),

        .mstatusOut(mstatusOut),
        .mieOut(mieOut),
        .mipOut(mipOut),
        .midelegOut(midelegOut),
        .satpOut(satpOut),

        .mode(mode),
        .pmpAddr(pmpAddr),
        .pmpCfg(pmpCfg),
        .csrIllegalAccess(csrIllegalAccess)
    );

    always #5 clock = ~clock;

    // ------------------------------------------------------------
    // Test helpers
    // ------------------------------------------------------------

    task automatic check(input logic cond, input string msg);
        if (cond !== 1'b1) begin
            errors++;
            $display("FAIL: %s (time=%0t)", msg, $time);
        end else begin
            $display("PASS: %s", msg);
        end
    endtask

    task automatic csrWrite(
        input logic [11:0] addr,
        input logic [31:0] val
    );
        @(negedge clock);
        address = addr;
        dataIn = val;
        op = 2'b01;
        readEnable = 1'b0;

        @(negedge clock);
        op = 2'b00;
        dataIn = '0;
        #1;
    endtask

    task automatic csrSet(
        input logic [11:0] addr,
        input logic [31:0] mask
    );
        @(negedge clock);
        address = addr;
        dataIn = mask;
        op = 2'b10;
        readEnable = 1'b0;

        @(negedge clock);
        op = 2'b00;
        dataIn = '0;
        #1;
    endtask

    task automatic csrClear(
        input logic [11:0] addr,
        input logic [31:0] mask
    );
        @(negedge clock);
        address = addr;
        dataIn = mask;
        op = 2'b11;
        readEnable = 1'b0;

        @(negedge clock);
        op = 2'b00;
        dataIn = '0;
        #1;
    endtask

    task automatic csrRead(
        input logic [11:0] addr,
        output logic [31:0] val
    );
        @(negedge clock);
        address = addr;
        op = 2'b00;
        readEnable = 1'b1;
        #1;
        val = dataOut;

        @(negedge clock);
        readEnable = 1'b0;
        #1;
    endtask

    task automatic checkLegal(
        input logic [11:0] addr,
        input logic expectedIllegal,
        input string msg
    );
        @(negedge clock);
        address = addr;
        op = 2'b00;
        readEnable = 1'b1;
        #1;
        check(csrIllegalAccess === expectedIllegal, msg);

        @(negedge clock);
        readEnable = 1'b0;
        #1;
    endtask

    // Keeps trapCause asserted after the trap so that trapTargetPC
    // continues to reflect the cause/delegation being tested.
    task automatic takeTrap(
        input logic [31:0] cause,
        input logic [31:0] pc,
        input logic [31:0] value
    );
        @(negedge clock);
        trapCause = cause;
        trapPC = pc;
        trapValue = value;
        trapTaken = 1'b1;
        #1;

        @(negedge clock);
        trapTaken = 1'b0;
        trapPC = '0;
        trapValue = '0;
        #1;
    endtask

    task automatic doMRET;
        @(negedge clock);
        isMRET = 1'b1;

        @(negedge clock);
        isMRET = 1'b0;
        #1;
    endtask

    task automatic doSRET;
        @(negedge clock);
        isSRET = 1'b1;

        @(negedge clock);
        isSRET = 1'b0;
        #1;
    endtask

    // ------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------

    initial begin
        clock = 1'b0;
        reset = 1'b1;
        retired = 1'b0;

        dataIn = '0;
        address = '0;
        op = 2'b00;
        readEnable = 1'b0;

        trapTaken = 1'b0;
        trapCause = '0;
        trapValue = '0;
        trapPC = '0;

        isMRET = 1'b0;
        isSRET = 1'b0;

        mtime = 64'h1234_5678_9ABC_DEF0;

        repeat (3) @(negedge clock);
        reset = 1'b0;
        repeat (2) @(negedge clock);

        // ========================================================
        // 1. Reset
        // ========================================================

        check(mode == MACHINE, "reset initializes mode to MACHINE");

        csrRead(12'h300, rd);
        check(rd == 32'h0000_0000, "mstatus resets to zero");

        csrRead(12'h301, rd);
        check(rd == 32'h4014_112D, "misa contains configured reset value");

        csrRead(12'h180, rd);
        check(rd == 32'h0000_0000, "satp resets to zero");

        check(mstatusOut == 32'h0, "mstatusOut resets to zero");
        check(mieOut == 32'h0, "mieOut resets to zero");
        check(mipOut == 32'h0, "mipOut resets to zero");
        check(midelegOut == 32'h0, "midelegOut resets to zero");
        check(satpOut == 32'h0, "satpOut resets to zero");

        // ========================================================
        // 2. CSR operations and output widths
        // ========================================================

        csrWrite(12'h300, 32'h0000_0008);
        csrRead(12'h300, rd);

        check(rd[3] == 1'b1, "CSRRW writes mstatus.MIE");
        check(mstatusOut[3] == 1'b1, "mstatusOut exposes MIE");

        csrWrite(12'h300, 32'h0);
        csrSet(12'h300, 32'h0000_0080);
        csrRead(12'h300, rd);

        check(rd[7] == 1'b1, "CSRRS sets MPIE");

        csrClear(12'h300, 32'h0000_0080);
        csrRead(12'h300, rd);

        check(rd[7] == 1'b0, "CSRRC clears MPIE");

        // ========================================================
        // 3. Machine trap must not delegate downward
        // ========================================================

        csrWrite(12'h305, 32'h0000_1000); // mtvec
        csrWrite(12'h302, 32'hFFFF_FFFF); // medeleg
        csrWrite(12'h300, 32'h0000_0008); // MIE = 1

        takeTrap(32'd2, 32'h0000_0500, 32'hDEAD_BEEF);

        check(mode == MACHINE, "M-mode trap remains in MACHINE");
        check(trapTargetPC == 32'h0000_1000,
              "M-mode trap target is mtvec");

        check(mretTargetPC == 32'h0000_0500,
              "mretTargetPC exposes mepc");

        csrRead(12'h341, rd);
        check(rd == 32'h0000_0500, "mepc captures trapPC");

        csrRead(12'h342, rd);
        check(rd == 32'd2, "mcause captures trapCause");

        csrRead(12'h343, rd);
        check(rd == 32'hDEAD_BEEF, "mtval captures trapValue");

        csrRead(12'h300, rd);
        check(rd[7] == 1'b1, "MPIE captures prior MIE");
        check(rd[3] == 1'b0, "trap clears MIE");
        check(rd[12:11] == 2'b11, "MPP captures MACHINE");

        // ========================================================
        // 4. MRET returns to MACHINE
        // ========================================================

        doMRET();

        check(mode == MACHINE, "MRET returns to MACHINE");

        csrRead(12'h300, rd);
        check(rd[3] == 1'b1, "MRET restores MIE");
        check(rd[7] == 1'b1, "MRET sets MPIE");
        check(rd[12:11] == 2'b00, "MRET clears MPP");

        // ========================================================
        // 5. M-mode privilege checks
        // ========================================================

        checkLegal(12'h300, 1'b0, "M-mode can read mstatus");
        checkLegal(12'h100, 1'b0, "M-mode can read sstatus");

        // ========================================================
        // 6. Enter S-mode via MRET
        // ========================================================

        csrWrite(12'h300, 32'h0000_0800); // MPP = S
        csrRead(12'h300, rd);
        check(rd[12:11] == 2'b01, "MPP is configured to S-mode");

        doMRET();

        check(mode == SUPERVISOR, "MRET with MPP=S enters S-mode");

        checkLegal(12'h300, 1'b1, "S-mode cannot read mstatus");
        checkLegal(12'h100, 1'b0, "S-mode can read sstatus");
        checkLegal(12'h105, 1'b0, "S-mode can read stvec");
        checkLegal(12'h140, 1'b0, "S-mode can read sscratch");
        checkLegal(12'hB00, 1'b1,
                   "S-mode cannot access machine cycle counter");

        // ========================================================
        // 7. Supervisor CSRs and SRET
        // ========================================================

        csrWrite(12'h105, 32'h0000_2000);
        csrRead(12'h105, rd);
        check(rd == 32'h0000_2000, "stvec write/read round-trip");

        csrWrite(12'h140, 32'hCAFE_BABE);
        csrRead(12'h140, rd);
        check(rd == 32'hCAFE_BABE, "sscratch write/read round-trip");

        // SPP = 0, SPIE = 1; SIE remains zero.
        csrWrite(12'h100, 32'h0000_0020);
        doSRET();

        check(mode == USER, "SRET with SPP=0 returns to USER");

        csrRead(12'h100, rd);
        check(rd[5] == 1'b1, "SRET sets SPIE");
        check(rd[8] == 1'b0, "SRET clears SPP");

        check(sretTargetPC == 32'h0000_0000,
              "sretTargetPC exposes sepc");

        checkLegal(12'h100, 1'b1, "U-mode cannot access sstatus");
        checkLegal(12'hC00, 1'b1,
                   "U-mode counter access denied with enables clear");

        // ========================================================
        // 8. Return from U-mode to M-mode through a trap
        // ========================================================

        // Cause 11 is not delegated: medeleg bit 11 is not set
        // by the current BM_MEDELEG mask.
        takeTrap(32'd11, 32'h0000_0700, 32'h0);

        check(mode == MACHINE,
              "non-delegated trap from U-mode enters MACHINE");

        check(trapTargetPC == 32'h0000_1000,
              "non-delegated U-mode trap targets mtvec");

        // ========================================================
        // 9. Delegated S-mode trap
        // ========================================================

        // All setup happens in M-mode.
        csrWrite(12'h302, 32'h0000_0004); // delegate exception 2
        csrWrite(12'h303, 32'h0000_0000); // clear mideleg
        csrWrite(12'h305, 32'h0000_1000);
        csrWrite(12'h105, 32'h0000_3000); // stvec

        csrWrite(12'h300, 32'h0000_0800); // MPP = S
        csrRead(12'h300, rd);
        check(rd[12:11] == 2'b01, "MPP=S before delegation test");

        doMRET();
        check(mode == SUPERVISOR,
              "MRET enters S-mode for delegation test");

        // SIE = 0 before the trap.
        csrWrite(12'h100, 32'h0000_0000);

        takeTrap(32'd2, 32'h0000_0600, 32'h0000_ABCD);

        check(mode == SUPERVISOR, "delegated exception enters S-mode");
        check(trapTargetPC == 32'h0000_3000,
              "delegated trap target is stvec");

        check(sretTargetPC == 32'h0000_0600,
              "sretTargetPC exposes captured sepc");

        csrRead(12'h141, rd);
        check(rd == 32'h0000_0600, "sepc captures trapPC");

        csrRead(12'h142, rd);
        check(rd == 32'd2, "scause captures delegated cause");

        csrRead(12'h143, rd);
        check(rd == 32'h0000_ABCD, "stval captures trapValue");

        csrRead(12'h100, rd);
        check(rd[5] == 1'b0, "SPIE captures prior SIE=0");
        check(rd[1] == 1'b0, "delegated trap clears SIE");
        check(rd[8] == 1'b1, "SPP records previous S-mode");

        // ========================================================
        // 10. Return to M-mode for machine-only CSR tests
        // ========================================================

        // Cause 11 is not delegated by the configured medeleg=bit 2.
        takeTrap(32'd11, 32'h0000_0800, 32'h0);

        check(mode == MACHINE,
              "non-delegated S-mode trap enters MACHINE");

        check(trapTargetPC == 32'h0000_1000,
              "machine trap targets mtvec");

        // ========================================================
        // 11. PMP registers
        // ========================================================

        csrWrite(12'h3A0, 32'h0000_00CF);
        csrRead(12'h3A0, rd);

        check(rd == 32'h0000_00CF, "pmpcfg0 write/read round-trip");

        csrWrite(12'h3B0, 32'h2000_0000);
        csrRead(12'h3B0, rd);

        check(rd == 32'h2000_0000, "pmpaddr0 write/read round-trip");

        csrWrite(12'h3B1, 32'h1234_5678);
        csrRead(12'h3B1, rd);

        check(rd == 32'h1234_5678, "pmpaddr1 write/read round-trip");

        // ========================================================
        // 12. SATP
        // ========================================================

        csrWrite(12'h180, 32'h8030_0123);
        csrRead(12'h180, rd);

        check(rd == (32'h8030_0123 & 32'h803F_FFFF),
              "satp applies BM_SATP mask");

        check(satpOut == rd, "satpOut matches satp");

        // ========================================================
        // 13. TIME
        // ========================================================

        mtime = 64'h1234_5678_9ABC_DEF0;

        csrRead(12'hC01, rd);
        check(rd == 32'h9ABC_DEF0, "time reads low mtime");

        csrRead(12'hC81, rd);
        check(rd == 32'h1234_5678, "timeh reads high mtime");

        // ========================================================
        // 14. Machine counters
        // ========================================================

        csrRead(12'hB00, rd);
        check(!$isunknown(rd), "mcycle low half is readable");

        csrRead(12'hB80, rd);
        check(!$isunknown(rd), "mcycle high half is readable");

        retired = 1'b1;
        repeat (3) @(negedge clock);
        retired = 1'b0;

        csrRead(12'hB02, rd);
        check(rd >= 32'd3, "minstret increments on retirement");

        // ========================================================
        // 15. mcountinhibit
        // ========================================================

        // This test is expected to FAIL against the supplied RTL:
        // MCI is decoded, but the read/write cases do not implement it.
        csrWrite(12'h320, 32'h0000_0005);
        csrRead(12'h320, rd);

        check(rd[0] == 1'b1 && rd[2] == 1'b1,
              "mcountinhibit stores CY and IR bits");

        // ========================================================
        // 16. Illegal CSR and read-enable behavior
        // ========================================================

        csrRead(12'hFFF, rd);
        check(rd == 32'h0000_0000, "illegal CSR reads as zero");

        // csrIllegalAccess is gated by readEnable and op.
        address = 12'hFFF;
        op = 2'b00;
        readEnable = 1'b0;
        #1;

        check(csrIllegalAccess == 1'b0,
              "illegal flag clears when readEnable and op are zero");

        address = 12'h300;
        readEnable = 1'b0;
        op = 2'b00;
        #1;

        check(dataOut == 32'h0000_0000,
              "dataOut is zero when readEnable is low");

        // ========================================================
        // Summary
        // ========================================================

        $display("");
        $display("=====================================");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);
        $display("=====================================");

        $dumpfile("csr_tb.vcd");
        $dumpvars(0, csr_tb);

        $finish;
    end

endmodule