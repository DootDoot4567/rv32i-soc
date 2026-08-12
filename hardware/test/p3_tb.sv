`default_nettype none
`timescale 1ns/1ps

module p3_tb;

    parameter MEMORY_INIT = "test2.mem";

    logic clock;
    logic reset;

    logic rxDataStream;
    logic txDataStream;


    initial clock = 0;
    always #5 clock = ~clock;


    soc #(
        .INIT(MEMORY_INIT)
    ) dut (
        .clock(clock),
        .reset(reset),

        .rxDataStream(rxDataStream),
        .txDataStream(txDataStream)
    );


    // BRAM is addressed by byte address, so convert to word index
    function automatic int word_idx(input logic [31:0] addr);
        word_idx = addr >> 2;
    endfunction



    task automatic step();

        logic [63:0] start;

        start = dut.processor_inst.instrRetired;

        @(posedge clock);

        while(dut.processor_inst.instrRetired === start)
            @(posedge clock);

    endtask



    task automatic expect_reg(
        int r,
        logic [31:0] expected,
        string msg
    );

        logic [31:0] actual;

        actual = dut.processor_inst.registerFile[r];

        if(actual !== expected)
        begin
            $error(
                "FAIL %-30s x%0d expected=%h got=%h",
                msg,
                r,
                expected,
                actual
            );

            $fatal;
        end

    endtask



    task automatic expect_mem(
        int addr,
        logic [31:0] expected,
        string msg
    );

        logic [31:0] actual;

        actual = dut.bram_inst.memory[word_idx(addr)];

        if(actual !== expected)
        begin
            $error(
                "FAIL %-30s addr=%h expected=%h got=%h",
                msg,
                addr,
                expected,
                actual
            );

            $fatal;
        end

    endtask



    localparam int WORD_0 = word_idx(32'h2100);
    localparam int WORD_4 = word_idx(32'h2104);
    localparam int WORD_8 = word_idx(32'h2108);



    initial
    begin

        $dumpfile("processor_mem_debug.vcd");
        $dumpvars(0,dut);


        rxDataStream = 1'b1;

        reset = 1;

        repeat(10)
            @(posedge clock);

        reset = 0;

        dut.bram_inst.memory[WORD_0] = 32'h0;
        dut.bram_inst.memory[WORD_4] = 32'h0;
        dut.bram_inst.memory[WORD_8] = 32'h0;



        // integer instructions

        step(); expect_reg(1, 32'h12345000,"lui");
        step(); expect_reg(2, 42,"addi");

        step(); expect_reg(3,1,"slti");
        step(); expect_reg(4,0,"sltiu");

        step(); expect_reg(5,37,"xori");
        step(); expect_reg(6,47,"ori");
        step(); expect_reg(7,10,"andi");

        step(); expect_reg(8,84,"slli");
        step(); expect_reg(9,21,"srli");
        step(); expect_reg(10,21,"srai");

        step(); expect_reg(11,126,"add");
        step(); expect_reg(12,42,"sub");

        step(); expect_reg(13,43008,"sll");

        step(); expect_reg(14,0,"slt");
        step(); expect_reg(15,1,"sltu");

        step(); expect_reg(16,84,"xor");
        step(); expect_reg(17,0,"srl");
        step(); expect_reg(18,0,"sra");

        step(); expect_reg(19,47,"or");
        step(); expect_reg(20,37,"and");



        // address generation

        step(); expect_reg(21,32'h2000,"lui x21");

        step(); expect_reg(21,32'h2100,"addi x21");



        // stores

        step();
        step();
        step();


        expect_mem(32'h2100,32'h0000007e,"sw");

        expect_mem(32'h2104,32'h002a007e,"sh/sb");



        // loads

        step(); expect_reg(22,126,"lw");
        step(); expect_reg(23,126,"lh");
        step(); expect_reg(24,126,"lhu");

        step(); expect_reg(25,42,"lb");
        step(); expect_reg(26,42,"lbu");

        step(); expect_reg(27,32'hffff8000,"lui");

        step();

        expect_mem(
            32'h2108,
            32'hffff8000,
            "store negative"
        );


        step(); expect_reg(28,32'hffff8000,"lh negative");
        step(); expect_reg(29,32'h00008000,"lhu negative");
        step(); expect_reg(30,32'hffffff80,"lb negative");
        step(); expect_reg(31,32'h00000080,"lbu negative");



        // branches

        step(); expect_reg(3,0,"branch init");

        step();

        step(); expect_reg(3,2,"beq target");

        step();

        step(); expect_reg(3,6,"after bne");

        step(); expect_reg(3,14,"after addi");



        // signed/unsigned branches

        step(); expect_reg(4,32'hffffffff,"negative");

        step(); expect_reg(5,1,"positive");

        step();

        step(); expect_reg(6,2,"blt");

        step();

        step(); expect_reg(7,1,"bltu");

        step(); expect_reg(7,9,"fallthrough");


        step();

        step(); expect_reg(8,2,"bge");


        step();

        step(); expect_reg(9,2,"bgeu");



        // jumps

        step(); expect_reg(13,0,"jal init");

        step();

        if(dut.processor_inst.registerFile[1] == 0)
        begin
            $error("JAL link failed");
            $fatal;
        end


        step();

        expect_reg(13,2,"jal result");


        step();
        step();
        step();


        step();

        expect_reg(14,2,"jalr");


        step();
        step();


        step();

        if(dut.processor_inst.registerFile[15] == 0)
        begin
            $error("JALR link failed");
            $fatal;
        end


        step();

        expect_reg(16,2,"jalr link");



        $display("Passed memory/fetch execution test.");

        $finish;

    end


endmodule