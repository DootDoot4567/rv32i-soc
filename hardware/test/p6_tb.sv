`default_nettype none
`timescale 1ns / 1ps

module p6_tb ();

    parameter MEMORY_INIT = "test2.mem";

    logic clock;
    logic clock4x;
    logic reset;
    logic interrupt;

    initial clock = 0;
    initial clock4x = 0;

    localparam CLOCK_HALF_PERIOD = 40;
    localparam CLOCK_4X_HALF_PERIOD = 10;

    always #(CLOCK_HALF_PERIOD) clock = ~clock;
    always #(CLOCK_4X_HALF_PERIOD) clock4x = ~clock4x;

    initial interrupt = 0;

    logic rxDataStream;
    logic txDataStream;

    soc #(
        .INIT(MEMORY_INIT)
    ) soc_inst (
        .clock,
        .reset,
        .rxDataStream,
        .txDataStream
    );


    // ============================================================
    // Helper functions
    // ============================================================

    task automatic step();
        logic [63:0] initial_retired;

        initial_retired =
            soc_inst.processor_inst.csr_instr.instrRetired;

        @(posedge clock);

        while (soc_inst.processor_inst.csr_instr.instrRetired === initial_retired)
        begin
            @(posedge clock);
        end

        #1;
    endtask


    task automatic expect_reg(
        input int r,
        input logic [31:0] expected,
        input string message
    );

        logic [31:0] found;

        found = soc_inst.processor_inst.registerFile[r];

        if (found !== expected)
            begin
                $error(
                    "FAIL %-32s x%0d expected=0x%08x got=0x%08x",
                    message,
                    r,
                    expected,
                    found
                );
                $fatal;
            end

    endtask


    task automatic expect_mem(
        input int addr,
        input logic [31:0] expected,
        input string message
    );

        logic [31:0] found;

        found = soc_inst.bram_inst.memory[(addr) >> 2];

        if (found !== expected)
            begin
                $error(
                    "FAIL %-32s mem[%0d] expected=0x%08x got=0x%08x",
                    message,
                    addr,
                    expected,
                    found
                );
                $fatal;
            end

    endtask


    task automatic expect_csr(
        input logic [31:0] found,
        input logic [31:0] expected,
        input string message
    );

        if (found !== expected)
            begin
                $error(
                    "FAIL %-32s csr expected=0x%08x got=0x%08x",
                    message,
                    expected,
                    found
                );
                $fatal;
            end

    endtask


    task automatic expect_nonzero(
        input int r,
        input string message
    );

        logic [31:0] found;

        found = soc_inst.processor_inst.registerFile[r];

        if (found === 32'h0)
            begin
                $error(
                    "FAIL %-32s x%0d expected non-zero got=0x%08x",
                    message,
                    r,
                    found
                );
                $fatal;
            end

    endtask


    task automatic wait_for_instruction(
        input logic [31:0] wanted
    );

        @(posedge clock);

        while (
            soc_inst.processor_inst.mw_instr !== wanted
        )
            begin
                @(posedge clock);
            end

    endtask


    localparam logic [31:0] NOP_INST =
        32'h0000_0013;

    localparam logic [31:0] FIRST_TRAP_INST =
        32'h3420_2f73;



    // ============================================================
    // Memory locations
    // x21 = 0x2100
    // ============================================================

    localparam int WORD_0 =
        32'h00002100;

    localparam int WORD_4 =
        32'h00002104;

    localparam int WORD_8 =
        32'h00002108;



    // ============================================================
    // Test
    // ============================================================

    initial begin

        $dumpfile("p6_tb.vcd");
        $dumpvars(0, soc_inst);


        
        // Allow memories to initialize

        repeat(10)
            @(posedge clock);


        // Clear data memory

        soc_inst.bram_inst.memory[WORD_0] = 32'h0;
        soc_inst.bram_inst.memory[WORD_4] = 32'h0;
        soc_inst.bram_inst.memory[WORD_8] = 32'h0;



        // ========================================================
        // Trap handler at 0x9000
        //
        // 9000: csrrs x30, mcause, x0
        // 9004: addi  x31, x0, 11
        // 9008: bne   x30, x31, +16
        // 900c: csrrs x31, mepc, x0
        // 9010: addi  x31, x31, 4
        // 9014: csrrw x0, mepc, x31
        // 9018: mret
        //
        // ========================================================

        soc_inst.bram_inst.memory['h400] =
            32'h3420_2f73;

        soc_inst.bram_inst.memory['h401] =
            32'h00b0_0f93;

        soc_inst.bram_inst.memory['h402] =
            32'h01ff_1863;

        soc_inst.bram_inst.memory['h403] =
            32'h3410_2ff3;

        soc_inst.bram_inst.memory['h404] =
            32'h004f_8f93;

        soc_inst.bram_inst.memory['h405] =
            32'h341f_9073;

        soc_inst.bram_inst.memory['h406] =
            32'h3020_0073;



        // Reset

        @(negedge clock);
        reset = 1;

        @(negedge clock);
        reset = 0;


        repeat(3)
            @(posedge clock);



        // ========================================================
        // Integer ALU tests
        // ========================================================


        // lui x1, 0x12345
        step();
        expect_reg(1,32'h1234_5000,"lui x1");


        // addi x2, x0,42
        step();
        expect_reg(2,42,"addi x2");


        // slti
        step();
        expect_reg(3,1,"slti x3");


        // sltiu
        step();
        expect_reg(4,0,"sltiu x4");


        // xori
        step();
        expect_reg(5,37,"xori x5");


        // ori
        step();
        expect_reg(6,47,"ori x6");


        // andi
        step();
        expect_reg(7,10,"andi x7");


        // slli
        step();
        expect_reg(8,84,"slli x8");


        // srli
        step();
        expect_reg(9,21,"srli x9");


        // srai
        step();
        expect_reg(10,21,"srai x10");


        // add
        step();
        expect_reg(11,126,"add x11");


        // sub
        step();
        expect_reg(12,42,"sub x12");


        // sll
        step();
        expect_reg(13,43008,"sll x13");


        // slt
        step();
        expect_reg(14,0,"slt x14");


        // sltu
        step();
        expect_reg(15,1,"sltu x15");


        // xor
        step();
        expect_reg(16,84,"xor x16");


        // srl
        step();
        expect_reg(17,0,"srl x17");


        // sra
        step();
        expect_reg(18,0,"sra x18");


        // or
        step();
        expect_reg(19,47,"or x19");


        // and
        step();
        expect_reg(20,37,"and x20");



        // ========================================================
        // Load/store tests
        // ========================================================


        // lui x21,0x2
        step();
        expect_reg(21,32'h2000,"lui x21");


        // addi x21,x21,0x100
        step();
        expect_reg(21,32'h2100,"base address");



        // //sw
        step();


        // // sh
        step();


        // // sb
        step();


        // expect_mem(
        //     WORD_0,
        //     32'h0000_007e,
        //     "sw result"
        // );

        // expect_mem(
        //     WORD_4,
        //     32'h002a_007e,
        //     "sb/sh result"
        // );


        // lw
        step();
        expect_reg(22,126,"lw x22");


        // lh
        step();
        expect_reg(23,126,"lh x23");


        // lhu
        step();
        expect_reg(24,126,"lhu x24");


        // lb
        step();
        expect_reg(25,42,"lb x25");


        // lbu
        step();
        expect_reg(26,42,"lbu x26");


        // lui x27
        step();
        expect_reg(27,32'hffff8000,"lui negative");


        // sw negative
        step();


        // expect_mem(
        //     WORD_8,
        //     32'hffff8000,
        //     "store negative"
        // );


        // lh signed
        step();
        expect_reg(28,32'hffff8000,"lh negative");


        // lhu unsigned
        step();
        expect_reg(29,32'h00008000,"lhu positive");


        // lb signed
        step();
        expect_reg(30,32'hffffff80,"lb negative");


        // lbu unsigned
        step();
        expect_reg(31,32'h00000080,"lbu positive");

        // ========================================================
        // Branch tests
        // ========================================================


        // addi x3,x0,0
        step();
        expect_reg(3,0,"branch init x3");


        // beq x0,x0,+8 taken
        step();


        // skipped:
        // addi x3,x3,1


        // addi x3,x3,2
        step();
        expect_reg(3,2,"beq taken");


        // bne x0,x0,+8 not taken
        step();


        // addi x3,x3,4
        step();
        expect_reg(3,6,"bne fallthrough");


        // addi x3,x3,8
        step();
        expect_reg(3,14,"branch accumulation");



        // signed comparison setup

        step();
        expect_reg(4,32'hffff_ffff,"addi x4=-1");


        step();
        expect_reg(5,1,"addi x5=1");



        // blt taken

        step();


        // skipped:
        // addi x6,x0,1


        step();
        expect_reg(6,2,"blt taken");



        // bltu not taken

        step();


        step();
        expect_reg(7,1,"bltu not taken first");


        step();
        expect_reg(7,9,"bltu fallthrough");



        // bge taken

        step();


        step();
        expect_reg(8,2,"bge taken");



        // bgeu taken

        step();


        step();
        expect_reg(9,2,"bgeu taken");



        // ========================================================
        // JAL/JALR tests
        // ========================================================


        // addi x13,x0,0

        step();
        expect_reg(13,0,"jal init");


        // jal x1,+8

        step();
        expect_nonzero(1,"jal link");



        // addi x13,x13,2

        step();
        expect_reg(13,2,"jal target");



        // auipc x2

        step();


        // addi x2,x2,16

        step();


        // jalr x0,x2,0

        step();



        // skipped:
        // addi x14,x0,1


        step();
        expect_reg(14,2,"jalr target");



        // second auipc/jalr link

        step();


        step();


        step();


        // skipped:
        // addi x16,x0,1


        step();

        expect_reg(
            16,
            2,
            "jalr link target"
        );



        // ========================================================
        // ECALL / MRET tests
        // ========================================================


        // lui x1,0x9

        step();

        expect_reg(
            1,
            32'h0000_9000,
            "trap vector"
        );



        // csrrw x0,mtvec,x1

        step();


        expect_csr(
            soc_inst.processor_inst.csr_instr.mtvec,
            32'h0000_9000,
            "mtvec write"
        );



        // Wait for ecall trap handler

        wait_for_instruction(
            FIRST_TRAP_INST
        );


        expect_csr(
            soc_inst.processor_inst.csr_instr.mcause,
            32'd11,
            "ecall cause"
        );


        expect_csr(
            soc_inst.processor_inst.csr_instr.mepc,
            32'h0000_8124,
            "ecall mepc"
        );



        // Handler:

        // csrrs x30,mcause,x0

        step();

        expect_reg(
            30,
            11,
            "handler mcause"
        );



        // addi x31,x0,11

        step();

        expect_reg(
            31,
            11,
            "handler constant"
        );



        // bne

        step();



        // csrrs x31,mepc,x0

        step();

        expect_reg(
            31,
            32'h0000_8124,
            "handler mepc"
        );



        // addi x31,x31,4

        step();

        expect_reg(
            31,
            32'h0000_8128,
            "handler increment"
        );



        // csrrw x0,mepc,x31

        step();


        expect_csr(
            soc_inst.processor_inst.csr_instr.mepc,
            32'h0000_8128,
            "new mepc"
        );



        // mret

        step();



        // instruction after ecall

        step();

        expect_reg(
            22,
            42,
            "returned after mret"
        );



        // ========================================================
        // Final instructions
        // ========================================================


        // addi x1,x0,-1

        step();

        expect_reg(
            1,
            32'hffff_ffff,
            "final addi"
        );



        // csrrw x0,mie,x1

        step();



        // csrrw x0,mstatus,x1

        step();



        // accumulation sequence

        step();

        expect_reg(
            23,
            1,
            "accumulate 1"
        );


        step();

        expect_reg(
            23,
            3,
            "accumulate 2"
        );


        step();

        expect_reg(
            23,
            7,
            "accumulate 4"
        );


        step();

        expect_reg(
            23,
            15,
            "accumulate 8"
        );



        // ebreak

        step();



        $display("Passed all tests.");

        $finish;

    end

endmodule