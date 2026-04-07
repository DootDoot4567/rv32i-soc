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
    localparam ADDR_WIDTH = $clog2(DEPTH);
    localparam BASE_ADDR = 32'h8000 >> 2;

    //CPU Bus
    logic writeEnable;
    logic readEnable;
    logic [ADDR_WIDTH - 1:0] addrRead;
    logic [ADDR_WIDTH - 1:0] addrWrite;
    logic [WIDTH - 1:0] dataWrite;
    logic [WIDTH - 1:0] busDataRead;

    //Active Address Bus
    logic [ADDR_WIDTH - 1:0] activeAddr;

    assign activeAddr = readEnable  ? addrRead  :
                        writeEnable ? addrWrite :
                        '0;


    logic [ADDR_WIDTH - 1:0] bramAddrRead;
    logic [ADDR_WIDTH - 1:0] bramAddrWrite;

    assign bramAddrRead  = addrRead  - BASE_ADDR;
    assign bramAddrWrite = addrWrite - BASE_ADDR;

    logic [WIDTH - 1:0] bramDataRead;

    //UART Bus
    logic [1:0] uartAddr;
    logic [31:0] uartDataRead;
    logic uartInterrupt;

    assign uartAddr = activeAddr[1:0]; 

    //Chip select signals
    logic uartSelected;
    logic bramSelected;

    assign busDataRead = uartSelected ? uartDataRead : bramDataRead;

    assign uartSelected = (activeAddr >= 12'h090) && (activeAddr <= 12'h093);

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
        .addrRead(bramAddrRead),
        .addrWrite(bramAddrWrite),
        .dataWrite,
        .dataRead(bramDataRead)
    );

    //Instantiate the UART (Top for both RX and TX)
    uart #(
        .CYCLES_PER_BIT(CYCLES_PER_BIT)
    ) uart_inst (
        .clock,
        .reset,
        .addrSelected(uartAddr),
        .writeEnable(writeEnable && uartSelected),
        .readEnable(readEnable && uartSelected),
        .dataWrite,
        .rxDataStream,
        .interrupt(uartInterrupt),
        .dataRead(uartDataRead),
        .txDataStream
    );

endmodule