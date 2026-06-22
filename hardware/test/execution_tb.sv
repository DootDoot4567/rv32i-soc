`default_nettype none
`timescale 1ns / 1ps

`define SIMULATION

module execution_tb();
    parameter INIT="instructions.mem";

    logic clock;

    initial clock = 0;

    localparam CLOCK_HALF_PERIOD = 40;  // 12.5 MHz

    always #(CLOCK_HALF_PERIOD) clock = ~clock;

    logic reset;

    processor #(
        .INIT(INIT)
    ) processor_inst (
        .clock,
        .reset
    );

    initial begin
        $dumpfile("execution_tb.vcd");
        $dumpvars(0, processor_inst);
        // Give SOC a moment to load MEM_INIT
        repeat (10) @(posedge clock);

        // Apply reset
        reset = 1;
        @(posedge clock);
        reset = 0;

        #10000000; // Run for 10 ms max
        $finish;
    end
endmodule