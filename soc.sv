module soc #(
    parameter INIT = "",
    parameter WIDTH = 32,
    parameter DEPTH = 16384
) (
    input logic clock,
    input logic reset)
);
    //BRAM inputs and outputs being declared as logic

    //Instatiate the processor
    processor #(
        .INIT(INIT)
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) processor_inst (
        .clock,
        .reset,
        .clockWrite(clock),
        .clockRead(clock),
        .writeEnable,
        .readEnable,
        .addrWrite(addrWrite),
        .addrRead(addrRead),
        .dataIn(dataIn),
        .dataOut(dataOut)
    );

    //Instatiate the BRAM (simple dual port)
    bram_sdp #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .INIT(INIT)
    ) bram_inst (
        .clockWrite(clock),
        .clockRead(clock),
        .writeEnable,
        .readEnable,
        .addrWrite(addrWrite),
        .addrRead(addrRead),
        .dataIn(dataIn),
        .dataOut(dataOut)
    );

endmodule