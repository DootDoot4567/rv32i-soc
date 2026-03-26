module soc #(
    parameter INIT = "",
    parameter WIDTH = 32,
    parameter DEPTH = 16384,
    parameter CYCLES_PER_BIT = 217
) (
    input logic clock,
    input logic reset,

    input logic rx,
    output logic tx
);
    //Computes minimum bits needed for the mem addresses using log_2(depth)
    localparam ADDR_WIDTH=$clog2(DEPTH);

    //UART 
    localparam 
    local

    //BRAM inputs and outputs being declared as logic
    logic writeEnable;
    logic readEnable;
    logic [ADDR_WIDTH - 1:0] addrRead;
    logic [ADDR_WIDTH - 1:0] addrWrite;
    logic [WIDTH - 1:0] dataIn;
    logic [WIDTH - 1:0] dataOut;

    //UART inputs and outputs being declared as logic
    logic [1:0] addr_select;
    logic rx;
    logic tx;

    //Chip select signals
    logic uart_selected;
    logic bram_selected;

    assign uart_selected = (addrWrite >= 12'h200 && addrWrite <= 12'h203);
    assign bram_selected = (addrWrite >= 12'h400);

    assign addr_select = uart_selected ? addrWrite[2:0] : 2'h3;

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

    //Instantiate the UART (Top for both RX and TX)
    uart #(
        .CYCLES_PER_BIT(CYCLES_PER_BIT)
    ) uart_inst (
        .clock,
        .reset,
        .addr_select,
        .rx(dataIn),
        .tx(dataOut)
    );

endmodule