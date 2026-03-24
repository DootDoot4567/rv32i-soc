module soc #(
    parameter INIT = "",
    parameter WIDTH = 32,
    parameter DEPTH = 16384
) (
    input logic clock,
    input logic reset
);

    //Computes minimum bits needed for the mem addresses using log_2(depth)
    localparam ADDR_WIDTH=$clog2(DEPTH);

    //BRAM inputs and outputs being declared as logic
    logic writeEnable;
    logic readEnable;
    logic [ADDR_WIDTH - 1:0] addrRead;
    logic [ADDR_WIDTH - 1:0] addrWrite;
    logic [WIDTH - 1:0] dataIn;
    logic [WIDTH - 1:0] dataOut;

    //Instatiate the processor
    processor #(
        .INIT(INIT),
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) processor_inst (
        .clock,
        .reset,
        .dataOut,
        .writeEnable,
        .readEnable,
        .addrWrite,
        .addrRead,
        .dataIn
    );

    //Instatiate the BRAM (simple dual port)
    bram_sdp #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT(INIT)
    ) bram_inst (
        .clockWrite(clock),
        .clockRead(clock),
        .writeEnable,
        .readEnable,
        .addrWrite,
        .addrRead,
        .dataIn,
        .dataOut
    );

endmodule