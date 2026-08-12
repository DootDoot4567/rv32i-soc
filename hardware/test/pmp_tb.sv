`timescale 1ns/1ps
import cpu_types_pkg::*;

module pmp_tb;
    logic [31:0] checkAddr;
    logic isWrite, isExec;
    mode_t currentMode;
    logic [63:0][31:0] pmpAddr;
    logic [15:0][31:0] pmpCfg;
    logic accessFault;

    int errors = 0;

    pmp #(.NUM_ENTRIES(16)) dut (
        .checkAddr(checkAddr), .isWrite(isWrite), .isExec(isExec),
        .currentMode(currentMode), .pmpAddr(pmpAddr), .pmpCfg(pmpCfg),
        .accessFault(accessFault)
    );

    task automatic check(input logic cond, input string msg);
        if (!cond) begin
            errors++;
            $display("FAIL: %s", msg);
        end else begin
            $display("PASS: %s", msg);
        end
    endtask

    initial begin
        pmpAddr = '0;
        pmpCfg  = '0;
        checkAddr = 0; isWrite = 0; isExec = 0;
        currentMode = MACHINE;
        #1;

        // --- Test 1: M-mode, no entries configured => always allowed ---
        checkAddr = 32'h1000; isExec = 1'b1;
        #1;
        check(accessFault == 1'b0, "M-mode, no PMP entries, access allowed");

        // --- Test 2: U-mode, no entries configured => denied ---
        currentMode = USER;
        #1;
        check(accessFault == 1'b1, "U-mode, no PMP entries, access denied by default");

        // --- Test 3: TOR region covering [0x1000, 0x2000), U-mode, R+W+X ---
        pmpAddr[0] = 32'h0000_0400; // hiBound = addr<<2 = 0x1000
        pmpCfg[0]  = 8'b0_0_01_111; // A=TOR(01), L=0, R=1,W=1,X=1
        currentMode = USER;
        checkAddr = 32'h0000_0800; isExec = 1'b1; isWrite = 1'b0;
        #1;
        check(accessFault == 1'b0, "U-mode exec inside TOR region with X set: allowed");

        checkAddr = 32'h0000_3000;
        #1;
        check(accessFault == 1'b1, "U-mode exec outside TOR region: denied");

        // --- Test 4: TOR region, write without W bit ---
        pmpCfg[0] = 8'b0_0_01_101; // R=1,W=0,X=1
        checkAddr = 32'h0000_0800; isWrite = 1'b1; isExec = 1'b0;
        #1;
        check(accessFault == 1'b1, "U-mode write denied when W bit clear");

        // --- Test 5: M-mode bypasses unlocked entry entirely ---
        currentMode = MACHINE;
        checkAddr = 32'h0000_3000; isWrite = 1'b0; isExec = 1'b1; // outside region, would fail in U-mode
        #1;
        check(accessFault == 1'b0, "M-mode bypasses PMP when entry unlocked, even outside match");

        // --- Test 6: M-mode respects locked (L=1) entry ---
        pmpCfg[0] = 8'b1_0_01_111; // L=1, TOR, RWX
        checkAddr = 32'h0000_0800; // inside region
        #1;
        check(accessFault == 1'b0, "M-mode, locked entry, inside region with perms: allowed");

        checkAddr = 32'h0000_3000; // outside region
        #1;
        check(accessFault == 1'b0, "M-mode, locked entry, no match on this address: allowed (L bit only applies when matched)");

        // --- Test 7: NA4 matching ---
        pmpAddr[1] = 32'h0000_0123;
        pmpCfg[1]  = 8'b0_0_10_111; // A=NA4(10), RWX
        currentMode = USER;
        checkAddr = {pmpAddr[1][31:2], 2'b00}; // exact NA4-aligned match
        isWrite = 1'b0; isExec = 1'b0;
        #1;
        check(accessFault == 1'b0, "NA4 exact match: allowed");

        // --- Test 8: NAPOT matching (4KB region aligned) ---
        // NAPOT encoding: trailing 1s indicate region size. For 4KB (0x1000) region
        // starting at 0x2000_0000: addr[31:2] = base[31:2] with low (log2(size)-3) bits = 1, terminated by 0
        // size=4096=2^12, so 12-2=10 trailing bits pattern: base>>2 with bits[9:0]=1, bit[10]=0 relative... 
        // simplest: use a known-good encoded value for base=0x40000000, size=0x1000
        pmpAddr[2] = (32'h4000_0000 >> 2) | ((32'h1000 >> 3) - 1); // NAPOT encoding
        pmpCfg[2]  = 8'b0_0_11_111; // A=NAPOT(11), RWX
        checkAddr = 32'h4000_0500; // inside the 4KB region
        #1;
        check(accessFault == 1'b0, "NAPOT region match: allowed");

        checkAddr = 32'h4000_2000; // outside the 4KB region
        #1;
        check(accessFault == 1'b1, "NAPOT region non-match: denied");

        $display("=====================================");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);
        $display("=====================================");

        $finish;
    end
endmodule