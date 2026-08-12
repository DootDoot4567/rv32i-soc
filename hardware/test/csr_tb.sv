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

    logic [31:0] dataOut, trapTargetPC, mretTargetPC, sretTargetPC;
    mode_t mode;

    logic [63:0][31:0] pmpAddr;
    logic [15:0][31:0] pmpCfg;
    logic csrIllegalAccess;

    int errors = 0;

    csr dut (
        .clock(clock), .reset(reset), .retired(retired),
        .dataIn(dataIn), .address(address), .op(op), .readEnable(readEnable),
        .trapTaken(trapTaken), .trapCause(trapCause), .trapValue(trapValue), .trapPC(trapPC),
        .isMRET(isMRET), .isSRET(isSRET),
        .dataOut(dataOut), .trapTargetPC(trapTargetPC), .mretTargetPC(mretTargetPC), .sretTargetPC(sretTargetPC),
        .mode(mode), .pmpAddr(pmpAddr), .pmpCfg(pmpCfg), .csrIllegalAccess(csrIllegalAccess)
    );

    always #5 clock = ~clock;

    task automatic csrWrite(input [11:0] addr, input [31:0] val);
        @(negedge clock);
        address = addr; dataIn = val; op = 2'b01; readEnable = 1'b0;
        @(negedge clock);
        op = 2'b00; readEnable = 1'b0;
    endtask

    task automatic csrSet(input [11:0] addr, input [31:0] mask);
        @(negedge clock);
        address = addr; dataIn = mask; op = 2'b10; readEnable = 1'b0;
        @(negedge clock);
        op = 2'b00;
    endtask

    task automatic csrClear(input [11:0] addr, input [31:0] mask);
        @(negedge clock);
        address = addr; dataIn = mask; op = 2'b11; readEnable = 1'b0;
        @(negedge clock);
        op = 2'b00;
    endtask

    task automatic csrRead(input [11:0] addr, output [31:0] val);
        @(negedge clock);
        address = addr; op = 2'b00; readEnable = 1'b1;
        #1; val = dataOut;
        @(negedge clock);
        readEnable = 1'b0;
    endtask

    task automatic check(input logic cond, input string msg);
        if (!cond) begin
            errors++;
            $display("FAIL: %s", msg);
        end else begin
            $display("PASS: %s", msg);
        end
    endtask

    logic [31:0] rd;

    initial begin
        clock = 0; reset = 1; retired = 0;
        dataIn = 0; address = 0; op = 0; readEnable = 0;
        trapTaken = 0; trapCause = 0; trapValue = 0; trapPC = 0;
        isMRET = 0; isSRET = 0;

        repeat (3) @(negedge clock);
        reset = 0;
        repeat (2) @(negedge clock);

        // --- reset state ---
        check(mode == MACHINE, "mode resets to MACHINE");

        // --- basic CSR read/write ---
        csrWrite(12'h300, 32'h0000_0008);
        csrRead(12'h300, rd);
        check(rd == 32'h0000_0008, "mstatus write/read round-trip");

        csrWrite(12'h300, 32'h0000_0000);
        csrSet(12'h300, 32'h0000_0080);
        csrRead(12'h300, rd);
        check(rd[7] == 1'b1, "CSRRS sets MPIE bit");

        csrClear(12'h300, 32'h0000_0080);
        csrRead(12'h300, rd);
        check(rd[7] == 1'b0, "CSRRC clears MPIE bit");

        // --- set up mtvec, then take a real trap from M-mode ---
        csrWrite(12'h305, 32'h0000_1000); // mtvec
        csrWrite(12'h302, 32'hFFFF_FFFF); // medeleg = all set, should NOT matter, still in M-mode

        trapPC = 32'h0000_0500;
        trapCause = 32'd2;
        trapValue = 32'hDEAD_BEEF;
        trapTaken = 1'b1;
        @(negedge clock);
        trapTaken = 1'b0;
        @(negedge clock);

        check(mode == MACHINE, "trap taken from M-mode stays in MACHINE regardless of medeleg");
        check(trapTargetPC == 32'h0000_1000, "trapTargetPC == mtvec (never delegates from M-mode)");

        csrRead(12'h341, rd); // mepc
        check(rd == 32'h0000_0500, "mepc captured trapPC");
        csrRead(12'h342, rd); // mcause
        check(rd == 32'd2, "mcause captured trapCause");
        csrRead(12'h343, rd); // mtval
        check(rd == 32'hDEAD_BEEF, "mtval captured trapValue");

        csrRead(12'h300, rd); // mstatus
        check(rd[7] == 1'b0, "MPIE reflects MIE before trap (was 0)");
        check(rd[12:11] == MACHINE, "MPP captured previous mode (MACHINE)");

        // --- MRET back ---
        isMRET = 1'b1;
        @(negedge clock);
        isMRET = 1'b0;
        @(negedge clock);
        check(mode == MACHINE, "MRET returns to MPP (MACHINE)");

        csrRead(12'h300, rd);
        check(rd[12:11] == 2'b00, "MPP cleared after MRET");
        check(rd[7] == 1'b1, "MPIE set to 1 after MRET");

        // --- privilege check: in MACHINE mode, all CSRs accessible ---
        address = 12'h300; readEnable = 1; op = 2'b00;
        #1;
        check(csrIllegalAccess == 1'b0, "M-mode access to M-mode CSR is legal");
        @(negedge clock); readEnable = 0;

        address = 12'h100; readEnable = 1; op = 2'b00; // sstatus, lower privilege
        #1;
        check(csrIllegalAccess == 1'b0, "M-mode access to S-mode CSR is legal (M >= S)");
        @(negedge clock); readEnable = 0;

        // --- Enter SUPERVISOR mode: write MPP, then MRET ---
        csrWrite(12'h300, 32'h0000_0800); // mstatus.MPP = 01 (SUPERVISOR), bits [12:11]

        isMRET = 1'b1;
        @(negedge clock);
        isMRET = 1'b0;
        @(negedge clock);

        check(mode == SUPERVISOR, "MRET with MPP=SUPERVISOR drops mode to SUPERVISOR");

        // --- privilege check now that we're actually in SUPERVISOR mode ---
        address = 12'h300; readEnable = 1; op = 2'b00; // mstatus, M-mode only
        #1;
        check(csrIllegalAccess == 1'b1, "S-mode access to M-mode CSR is illegal (real mode, no force)");
        @(negedge clock); readEnable = 0;

        address = 12'h100; readEnable = 1; op = 2'b00; // sstatus, S-mode
        #1;
        check(csrIllegalAccess == 1'b0, "S-mode access to S-mode CSR is legal (real mode, no force)");
        @(negedge clock); readEnable = 0;

        // --- PMP CSR passthrough ---
        csrWrite(12'h3A0, 32'h0000_00CF);
        csrRead(12'h3A0, rd);
        check(rd == 32'h0000_00CF, "pmpcfg0 write/read round-trip");

        csrWrite(12'h3B0, 32'h2000_0000);
        csrRead(12'h3B0, rd);
        check(rd == 32'h2000_0000, "pmpaddr0 write/read round-trip");

        // --- illegal address ---
        csrRead(12'hFFF, rd);
        check(rd == 32'h0000_0000, "illegal address reads as 0");

        $display("=====================================");
        if (errors == 0)
            $display("ALL TESTS PASSED (M-mode-only coverage — see note on SUPERVISOR/USER gap)");
        else
            $display("%0d TEST(S) FAILED", errors);
        $display("=====================================");

        $finish;
    end
endmodule