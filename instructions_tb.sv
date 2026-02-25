`default_nettype none
`timescale 1ns / 1ps

`define SIMULATION

module instructions_tb ();
    parameter MEMORY_INIT="instructions.mem";

    logic clock;
    //logic clock4x;

    initial clock = 0;
    //initial clock4x = 0;

    localparam CLOCK_HALF_PERIOD = 40;  // 12.5 MHz
    //localparam CLOCK_4X_HALF_PERIOD = 10;  // 50 MHz

    always #(CLOCK_HALF_PERIOD) clock = ~clock;
    //always #(CLOCK_4X_HALF_PERIOD) clock4x = ~clock4x;

    logic reset;

    processor #(
        .INIT(MEMORY_INIT)
    ) processor_inst (
        .clock(clock),
        .reset(reset)
    );

    // Helper methods

    task automatic step(int cycles = 5);
        repeat (cycles) @(posedge clock);
    endtask

    task automatic expect_reg(int r, logic [31:0] expected, string message);
        logic [31:0] found = processor_inst.registerFile[r];

        if (found !== expected) 
            begin
                $error("FAIL %-28s x%0d expected=0x%08x got=0x%08x", message, r, expected, found);
                $fatal;
            end
    endtask

    task automatic expect_mem(int addr, logic [31:0] expected, string message);
        logic [31:0] found = processor_inst.bram_inst.memory[addr];

        if (found !== expected) begin
            $error("FAIL %-28s mem[%0d] expected=0x%08x got=0x%08x", message, addr, expected, found);
            $fatal;
        end
    endtask

    task automatic expect_nonzero(int r, string message);
        logic [31:0] found = processor_inst.registerFile[r]; 

        if (found === 32'h0) begin
            $error("FAIL %-28s x%0d expected non-zero, got 0x%08x", message, r, found);
            $fatal;
        end
    endtask

    // Address helpers for data checks (we use x21 = 0x00002100 as base)

    localparam int WORD_0 = 32'h00002100 >> 2; // 0x2100 / 4 = 0x840
    localparam int WORD_4 = 32'h00002104 >> 2; // 0x841
    localparam int WORD_8 = 32'h00002108 >> 2; // 0x842

    initial begin
        $dumpfile("instructions_tb.vcd");

        $dumpvars(0, processor_inst, processor_inst.bram_inst);
        // Give SOC a moment to load MEM_INIT
        repeat (10) @(posedge clock);

        processor_inst.bram_inst.memory[WORD_0] = 32'h123450b7;
        processor_inst.bram_inst.memory[WORD_4] = 32'h02a00113;
        processor_inst.bram_inst.memory[WORD_8] = 32'h03212193;

        // Apply reset
        @(negedge clock);
        reset = 1;
        @(negedge clock);
        reset = 0;

        // Execute the remaining of the initialization state
        @(posedge clock);

        // Execute through the FE state
        @(posedge clock);

        // We execute through FE state of the next instruction to get the results of the WB
        // of the previous instruction

        // ====== Step-by-step checks (must match program_test.asm order) ======

        // 0  LUI   x1, 0x12345
        step(); expect_reg(1, 32'h1234_5000, "lui x1, 0x12345");

        // 1  ADDI  x2, x0, 42
        step(); expect_reg(2, 32'd42, "addi x2, x0, 42");

        // 2  SLTI  x3, x2, 50 => 1
        step(); expect_reg(3, 32'd1, "slti x3, x2, 50");

        // 3  SLTIU x4, x2, 40 => 0
        step(); expect_reg(4, 32'd0, "sltiu x4, x2, 40");

        // 4  XORI  x5, x2, 0x0f => 37
        step(); expect_reg(5, 32'd37, "xori x5, x2, 0x0f");

        // 5  ORI   x6, x2, 0x0f => 47
        step(); expect_reg(6, 32'd47, "ori x6, x2, 0x0f");

        // 6  ANDI  x7, x2, 0x0f => 10
        step(); expect_reg(7, 32'd10, "andi x7, x2, 0x0f");

        // 7  SLLI  x8, x2, 1 => 84
        step(); expect_reg(8, 32'd84, "slli x8, x2, 1");

        // 8  SRLI  x9, x2, 1 => 21
        step(); expect_reg(9, 32'd21, "srli x9, x2, 1");

        // 9  SRAI  x10, x2, 1 => 21
        step(); expect_reg(10, 32'd21, "srai x10, x2, 1");

        // 10 ADD   x11, x2, x8 => 126
        step(); expect_reg(11, 32'd126, "add x11, x2, x8");

        // 11 SUB   x12, x8, x2 => 42
        step(); expect_reg(12, 32'd42, "sub x12, x8, x2");

        // 12 SLL   x13, x2, x7 => 42 << 10 = 43008
        step(); expect_reg(13, 32'd43008, "sll x13, x2, x7");

        // 13 SLT   x14, x2, x0 => 0
        step(); expect_reg(14, 32'd0, "slt x14, x2, x0");

        // 14 SLTU  x15, x0, x2 => 1
        step(); expect_reg(15, 32'd1, "sltu x15, x0, x2");

        // 15 XOR   x16, x11, x12 => 84
        step(); expect_reg(16, 32'd84, "xor x16, x11, x12");

        // 16 SRL   x17, x8, x7 => 0
        step(); expect_reg(17, 32'd0, "srl x17, x8, x7");

        // 17 SRA   x18, x2, x7 => 0
        step(); expect_reg(18, 32'd0, "sra x18, x2, x7");

        // 18 OR    x19, x5, x6 => 47
        step(); expect_reg(19, 32'd47, "or x19, x5, x6");

        // 19 AND   x20, x5, x6 => 37
        step(); expect_reg(20, 32'd37, "and x20, x5, x6");

        // 20 LUI   x21, 0x2  => 0x00002000
        step(); expect_reg(21, 32'h0000_2000, "lui x21, 0x2");

        // 21 ADDI  x21, x21, 0x100 => 0x00002100
        step(); expect_reg(21, 32'h0000_2100, "addi x21, x21, 0x100");

        // 22 SW    x11, 0(x21) -> mem[0x2100] = 0x0000007E
        step(); expect_mem(WORD_0, 32'h0000_007E, "sw x11, 0(x21)");

        // 23 SH    x11, 4(x21) -> mem[0x2104][15:0] = 0x007E
        step(); expect_mem(WORD_4, 32'h0000_007E, "sh x11, 4(x21)");

        // 24 SB    x12, 6(x21) -> mem[0x2106] byte = 0x2A => word 0x002A007E
        step(); expect_mem(WORD_4, 32'h002A_007E, "sb x12, 6(x21)");

        // 25 LW    x22, 0(x21) => 126
        step(); expect_reg(22, 32'd126, "lw x22, 0(x21)");

        // 26 LH    x23, 4(x21) => 126
        step(); expect_reg(23, 32'd126, "lh x23, 4(x21)");

        // 27 LHU   x24, 4(x21) => 126
        step(); expect_reg(24, 32'd126, "lhu x24, 4(x21)");

        // 28 LB    x25, 6(x21) => 42 (sign+)
        step(); expect_reg(25, 32'd42, "lb x25, 6(x21)");

        // 29 LBU   x26, 6(x21) => 42
        step(); expect_reg(26, 32'd42, "lbu x26, 6(x21)");

        // 30 LUI   x27, 0xFFFF8 => 0xFFFF8000
        step(); expect_reg(27, 32'hFFFF_8000, "lui x27, 0xFFFF8");

        // 31 SW    x27, 8(x21) -> mem[0x2108] = 0xFFFF8000
        step(); expect_mem(WORD_8, 32'hFFFF_8000, "sw x27, 8(x21)");

        // 32 LH    x28, 8(x21) => 0xFFFF8000 (-32768)
        step(); expect_reg(28, 32'hFFFF_8000, "lh x28, 8(x21)");

        // 33 LHU   x29, 8(x21) => 0x00008000
        step(); expect_reg(29, 32'h0000_8000, "lhu x29, 8(x21)");

        // 34 LB    x30, 9(x21) => 0xFFFFFF80 (-128)
        step(); expect_reg(30, 32'hFFFF_FF80, "lb x30, 9(x21)");

        // 35 LBU   x31, 9(x21) => 0x00000080
        step(); expect_reg(31, 32'h0000_0080, "lbu x31, 9(x21)");

        // 36 ADDI  x3, x0, 0
        step(); expect_reg(3, 32'd0, "addi x3, x0, 0");

        // 37 BEQ   x0, x0, +8 (taken), skip next
        step();

        // 38 ADDI  x3, x3, 1 (skipped)
        // step();

        // 39 ADDI  x3, x3, 2 => x3 = 2
        step(); expect_reg(3, 32'd2, "addi x3, x3, 2 (after beq)");

        // 40 BNE   x0, x0, +8 (not taken)
        step();

        // 41 ADDI  x3, x3, 4
        step(); expect_reg(3, 32'd6, "addi x3, x3, 4");

        // 42 ADDI  x3, x3, 8
        step(); expect_reg(3, 32'd14, "addi x3, x3, 8");

        // 43 ADDI  x4, x0, -1
        step(); expect_reg(4, 32'hFFFF_FFFF, "addi x4, x0, -1");

        // 44 ADDI  x5, x0, 1
        step(); expect_reg(5, 32'd1, "addi x5, x0, 1");

        // 45 BLT   x4, x5, +8 (taken)
        step();

        // 46 ADDI  x6, x0, 1 (skipped)
        // step();

        // 47 ADDI  x6, x0, 2 => x6 = 2
        step(); expect_reg(6, 32'd2, "addi x6, x0, 2 (after blt taken)");

        // 48 BLTU  x4, x5, +8 (not taken)
        step();

        // 49 ADDI  x7, x0, 1 => executed
        step(); expect_reg(7, 32'd1, "addi x7, x0, 1 (bltu not taken)");

        // 50 ADDI  x7, x0, 9 => executed
        step(); expect_reg(7, 32'd9, "addi x7, x0, 9 (fall-through)");

        // 51 BGE   x5, x4, +8 (taken)
        step();

        // 52 ADDI  x8, x0, 1 (skipped)
        // step();

        // 53 ADDI  x8, x0, 2 => x8 = 2
        step(); expect_reg(8, 32'd2, "addi x8, x0, 2 (after bge taken)");

        // 54 BGEU  x4, x5, +8 (taken)
        step();

        // 55 ADDI  x9, x0, 1 (skipped)
        // step();

        // 56 ADDI  x9, x0, 2 => x9 = 2
        step(); expect_reg(9, 32'd2, "addi x9, x0, 2 (after bgeu taken)");

        // 57 ADDI  x13, x0, 0
        step(); expect_reg(13, 32'd0, "addi x13, x0, 0");

        // 58 JAL   x1, +8 (link set, skip next)
        step(); expect_nonzero(1, "jal link (x1) non-zero");

        // 59 ADDI  x13, x13, 1 (skipped)
        // step();

        // 60 ADDI  x13, x13, 2 => x13 = 2
        step(); expect_reg(13, 32'd2, "addi x13, x13, 2 (after jal)");

        // 61 AUIPC x2, 0       (PC-relative; no exact value asserted)
        step();

        // 62 ADDI  x2, x2, 16   (target = PC+16)
        step();

        // 63 JALR  x0, x2, 0   (jump)
        step();

        // 64 ADDI  x14, x0, 1 (skipped)
        // step();

        // 65 ADDI  x14, x0, 2 => x14 = 2
        step(); expect_reg(14, 32'd2, "addi x14, x0, 2 (after jalr)");

        // 66 AUIPC x3, 0
        step();

        // 67 ADDI  x3, x3, 16
        step();

        // 68 JALR  x15, x3, 0 (with link)
        step(); expect_nonzero(15, "jalr link (x15) non-zero");

        // 69 ADDI  x16, x0, 1 (skipped)
        // step();

        // 70 ADDI  x16, x0, 2 => x16 = 2
        step(); expect_reg(16, 32'd2, "addi x16, x0, 2 (after jalr link)");

        // 71 ECALL (environment-defined; no state check here)
        // step();

        // 72 EBREAK (often used to end sim; no state check here)
        // step();

        $display("Passed all tests.");
        $finish;
        end
endmodule