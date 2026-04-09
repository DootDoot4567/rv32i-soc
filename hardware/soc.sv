module soc #(
    parameter INIT = "",
    parameter WIDTH = 32,
    parameter DEPTH = 65536,
    parameter CYCLES_PER_BIT = 217
) (
    input logic clock,
    input logic reset,

    input logic rxDataStream,
    output logic txDataStream
);
    //Computes minimum bits needed for the mem addresses using log_2(depth)
    // localparam ADDR_WIDTH = $clog2(DEPTH);
    localparam ADDR_WIDTH = 32;

    //Address offsets based on memory map declared in linker
    localparam ROM_BASE = 32'h8000;
    localparam RAM_BASE = 32'h0400;
    localparam ROM_SIZE_BYTES = (32'h8000) * 4;
    localparam RAM_SIZE_BYTES = (32'h8000 - 32'h0400) * 4;
    localparam UART_BASE = 32'h0240;
    localparam UART_NUM_BYTES = 4;

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
    logic uartInterrupt;
    logic [7:0] uartDataRead8;
    logic [7:0] uartDataWrite8;

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

    assign uartSelected = (activeAddr >= UART_BASE) &&
                      (activeAddr < UART_BASE + UART_NUM_BYTES);

    assign bramSelected = !uartSelected && (romSelected || ramSelected);

    assign romSelected = (activeAddr >= ROM_BASE) && 
                         (activeAddr < ROM_BASE + ROM_SIZE_BYTES);
    assign ramSelected = (activeAddr >= RAM_BASE) &&
                         (activeAddr < RAM_BASE + RAM_SIZE_BYTES);

    assign romReadSelected = (addrRead >= ROM_BASE) &&
                             (addrRead < ROM_BASE + ROM_SIZE_BYTES);

    assign ramReadSelected = (addrRead >= RAM_BASE) &&
                             (addrRead < RAM_BASE + RAM_SIZE_BYTES);

    assign ramWriteSelected = (addrWrite >= RAM_BASE) &&
                              (addrWrite < RAM_BASE + RAM_SIZE_BYTES);

    assign bramAddrRead = romSelected ? ((addrRead - ROM_BASE) >> 2) :
                          ramSelected ? ((addrRead - RAM_BASE) >> 2) : '0;

    assign bramAddrWrite = ramWriteSelected ? ((addrWrite - RAM_BASE) >> 2) : '0;
    
    always @(*)
        begin
            case (addrWrite[1:0])
                2'b00: uartDataWrite8 = dataWrite[7:0];
                2'b01: uartDataWrite8 = dataWrite[15:8];
                2'b10: uartDataWrite8 = dataWrite[23:16];
                2'b11: uartDataWrite8 = dataWrite[31:24];
                default: 
                    begin
                        uartDataWrite8 = 8'h00;
                    end
            endcase
        end

    assign busDataRead = uartSelected ? {uartDataRead8, 
                                         uartDataRead8, 
                                         uartDataRead8, 
                                         uartDataRead8} : bramDataRead;

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
        .dataWrite(uartDataWrite8),
        .rxDataStream,
        .interrupt(uartInterrupt),
        .dataRead(uartDataRead8),
        .txDataStream
    );

endmodule