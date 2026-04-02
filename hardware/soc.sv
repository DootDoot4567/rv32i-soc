module soc #(
    parameter INIT = "",
    parameter WIDTH = 32,
    parameter DEPTH = 16384,
    parameter CYCLES_PER_BIT = 217
) (
    input logic clock,
    input logic reset,

    input logic rxDataStream,
    output logic txDataStream
);
    //Computes minimum bits needed for the mem addresses using log_2(depth)
    localparam ADDR_WIDTH=$clog2(DEPTH);

    //CPU Bus
    logic writeEnable;
    logic readEnable;
    logic [ADDR_WIDTH - 1:0] addrRead;
    logic [ADDR_WIDTH - 1:0] addrWrite;
    logic [WIDTH - 1:0] dataWrite;
    logic [WIDTH - 1:0] busDataRead;

    logic [WIDTH-1:0] bramDataRead;

    //UART Bus
    logic [1:0] addrSelected;
    logic [31:0] uartDataRead;
    logic uartInterrupt;

    assign addrSelected = readEnable ? addrRead : 
                                       (writeEnable ? addrWrite : 'd0);

    //Chip select signals
    logic uartSelected;
    logic bramSelected;

    assign busDataRead = uartSelected ? uartDataRead : bramDataRead;

    assign uartSelected = (addrWrite >= 12'h240 && addrWrite <= 12'h243) || 
                           (addrRead >= 12'h240 && addrRead <= 12'h243);

    assign bramSelected = !uartSelected;

    //Instatiate the processor
    processor #(
        .INIT(INIT),
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) processor_inst (
        .clock,
        .reset,
        .dataRead(busDataRead),
        .writeEnable,
        .readEnable,
        .addrWrite,
        .addrRead,
        .dataWrite
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
        .writeEnable(writeEnable && bramSelected),
        .readEnable(readEnable && bramSelected),
        .addrWrite,
        .addrRead,
        .dataWrite,
        .dataRead(bramDataRead)
    );

    //Instantiate the UART (Top for both RX and TX)
    uart #(
        .CYCLES_PER_BIT(CYCLES_PER_BIT)
    ) uart_inst (
        .clock,
        .reset,
        .addrSelected,
        .writeEnable(writeEnable && uartSelected),
        .readEnable(readEnable && uartSelected),
        .dataWrite,
        .rxDataStream,
        .interrupt(uartInterrupt),
        .dataRead(uartDataRead),
        .txDataStream
    );

endmodule