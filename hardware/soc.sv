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

    //Address offsets based on memory map declared in linker
    localparam ROM_BASE = 32'h8000 >> 2;
    localparam RAM_BASE = 32'h0400 >> 2;
    localparam UART_BASE_WORD = 32'h0240 >> 2;
    localparam UART_NUM_WORDS = 3;

    /////////
    // BUS //
    /////////

    //CPU
    logic writeEnable;
    logic readEnable;
    logic [ADDR_WIDTH - 1:0] addrRead;
    logic [ADDR_WIDTH - 1:0] addrWrite;
    logic [WIDTH - 1:0] dataWrite;
    logic [WIDTH - 1:0] busDataRead;
    logic [3:0] bramWriteMask;

    //Active Address
    logic [ADDR_WIDTH - 1:0] activeAddr;

    //UART
    logic [1:0] uartAddr;
    logic [31:0] uartDataRead;
    logic uartInterrupt;

    //BRAM
    logic [ADDR_WIDTH - 1:0] bramAddrRead;
    logic [ADDR_WIDTH - 1:0] bramAddrWrite;
    logic [WIDTH - 1:0] bramDataRead;

    //Chip select signals
    logic uartSelected;
    logic bramSelected;

    //Memory map signals
    logic romSelected;
    logic ramSelected;
    logic romReadSelected;
    logic ramReadSelected;
    logic ramWriteSelected;

    assign activeAddr = readEnable ? addrRead :
                      writeEnable ? addrWrite : '0;

    assign uartAddr = activeAddr[1:0]; 

    //assign uartSelected = (activeAddr >= 12'h090) && (activeAddr <= 12'h093);
    //assign uartSelected = (activeAddr >= RAM_BASE) && (activeAddr < RAM_BASE + 4);
    assign uartSelected = (activeAddr >= UART_BASE_WORD) &&
                      (activeAddr < UART_BASE_WORD + UART_NUM_WORDS);

    assign bramSelected = !uartSelected && (romSelected || ramSelected);

    assign romSelected = (activeAddr >= ROM_BASE);
    assign ramSelected = (activeAddr >= RAM_BASE) && (activeAddr < ROM_BASE);

    assign romReadSelected  = (addrRead  >= ROM_BASE);
    assign ramReadSelected  = (addrRead  >= RAM_BASE) && (addrRead  < ROM_BASE);
    assign ramWriteSelected = (addrWrite >= RAM_BASE) && (addrWrite < ROM_BASE);


    assign bramAddrRead = romSelected ? (activeAddr - ROM_BASE) : (activeAddr - RAM_BASE);
    assign bramAddrWrite = addrWrite - RAM_BASE;
    

    assign busDataRead = uartSelected ? uartDataRead : bramDataRead;

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
        .dataWrite,
        .bramWriteMask
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
        .bramWriteMask,
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