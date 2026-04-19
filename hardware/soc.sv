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
    localparam ADDR_WIDTH = $clog2(DEPTH);

    //Address offsets based on memory map
    localparam ROM_BASE = 32'h00008000;
    localparam UART_BASE = 32'h0340;
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
    logic [WIDTH - 1:0] dataRead;
    logic [3:0] bramWriteMask;

    //Active Address
    logic [ADDR_WIDTH - 1:0] address;

    //UART
    logic [1:0] uartAddr;

    logic uartInterrupt;
    logic uartReadFire;
    logic uartResponseValid;
    logic uartRead;
    logic uartWrite;

    logic [7:0] uartDataRead8;
    logic [7:0] uartDataWrite8;
    logic [7:0] uartReadHold;

    //BRAM
    logic [ADDR_WIDTH - 1:0] bramAddrRead;
    logic [ADDR_WIDTH - 1:0] bramAddrWrite;
    logic [WIDTH - 1:0] bramDataRead;

    //Chip select signals
    logic uartSelected;
    logic bramSelected;

    //Address for decoding (use read address if reading, write address if writing
    assign address = readEnable ? addrRead : (writeEnable ? addrWrite : 'd0);

    //If UART needs operation, select last 2 bits of either write or read addresses
    assign uartAddr = uartRead ? addrRead[1:0] : uartWrite ? addrWrite[1:0] : 2'b00;

    //Select uart if read or write is high while enable signal also being high
    assign uartSelected = (uartReadFire) || (uartWrite && writeEnable);
    assign uartReadFire = uartRead && readEnable;

    //Outside of IO region (Ideally).
    //Most likely needs to be fixed to prevent writes to addresses below 0x400
    assign bramSelected = !uartSelected;

    //Need a UART read if the address to read is within device installation
    assign uartRead =
        (addrRead >= UART_BASE) &&
        (addrRead < UART_BASE + UART_NUM_BYTES);

    //Need a UART write if the address to read is within device installation
    assign uartWrite =
        (addrWrite >= UART_BASE) &&
        (addrWrite < UART_BASE + UART_NUM_BYTES);

    //Select last byte of the data written (from CPU)
    assign uartDataWrite8 = dataWrite[7:0];

    //Offset the addresses since the .mem file lives in ROM
    assign bramAddrRead  = (addrRead  - ROM_BASE) >> 2;
    assign bramAddrWrite = (addrWrite - ROM_BASE) >> 2;

    always_ff @(posedge clock or posedge reset) 
        begin
            if (reset) 
                begin
                    //If reset, do not respond or hold any data
                    uartResponseValid <= 1'b0;
                    uartReadHold  <= 8'h00;
                end 
            else 
                begin
                    //Creates a one cycle delay to keep data fed into UART stable
                    //Do not hold any data by default
                    uartResponseValid <= 1'b0;

                    //If CPU reaches UART's read address and enable is up  
                    if (uartReadFire) 
                        begin
                            //Hold read data byte for one cycle and respond
                            uartReadHold  <= uartDataRead8;
                            uartResponseValid <= 1'b1;
                        end
                end
        end

    assign dataRead = (uartReadFire || uartResponseValid) ? 
        {uartReadHold, 
         uartReadHold, 
         uartReadHold, 
         uartReadHold} : bramDataRead;

    processor #(
        .INIT(INIT),
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RESET_ADDRESS(ROM_BASE)
    ) processor_inst (
        .clock,
        .reset,
        .dataRead,
        .writeEnable,
        .readEnable,
        .addrRead,
        .addrWrite,
        .dataWrite,
        .bramWriteMask
    );

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

    uart #(
        .CYCLES_PER_BIT(CYCLES_PER_BIT)
    ) uart_inst (
        .clock,
        .reset,
        .addrSelected(uartAddr),
        .writeEnable(uartWrite && writeEnable),
        .readEnable(uartRead && readEnable),
        .dataWrite(uartDataWrite8),
        .rxDataStream,
        .interrupt(uartInterrupt),
        .dataRead(uartDataRead8),
        .txDataStream
    );

endmodule