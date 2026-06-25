module uart #(
    parameter CYCLES_PER_BIT = 217,
    parameter ADDR_WIDTH = 16,
    parameter WIDTH = 32
) (
    input logic clock,
    input logic reset,
    input logic rxDataStream,

    input logic [ADDR_WIDTH - 1:0] addrIn,
    input logic [WIDTH - 1:0] dataIn,
    input logic [3:0] selectIn,
    input logic strobeIn,
    input logic cycleIn,
    input logic writeEnableIn,

    output logic stallOut,
    output logic interrupt,
    output logic acknowledgedOut,
    output logic [WIDTH - 1:0] dataOut,

    output logic txDataStream
);
    logic txActive;

    //Parallel data from TX and RX
    logic [7:0] txByteData;
    logic [7:0] rxByteData;

    //Data availability signals for TX and RX
    logic txDataValid;
    logic rxDataValid;

    //FIFO status signals
    logic txReadEnable;
    logic txWriteEnable;
    logic txEmpty;
    logic txFull;

    logic rxReadEnable;
    logic rxWriteEnable;
    logic rxEmpty;
    logic rxFull;

    //FIFO Data registers
    logic [7:0] txDataRead;
    logic [7:0] txDataWrite;

    logic [7:0] rxDataRead;
    logic [7:0] rxDataWrite;

    //Decode internal signals from port
    logic [1:0] addrSelected;
    logic [7:0] dataWrite;
    logic [7:0] dataRead;

    uart_rx #(
        .CYCLES_PER_BIT(CYCLES_PER_BIT)
    ) uart_rx_inst (
        .clock,
        .rxDataStream,
        .rxDataValid(rxDataValid),
        .rxByteData(rxDataWrite)
    );

    fifo #(
        .DEPTH(16),
        .WIDTH(8)
    ) rx_fifo_inst (
        .clock,
        .reset,
        .writeEnable(rxWriteEnable),
        .readEnable(rxReadEnable),
        .dataRead(rxDataRead),
        .dataWrite(rxDataWrite),
        .empty(rxEmpty),
        .full(rxFull)
    );

    uart_tx #(
        .CYCLES_PER_BIT(CYCLES_PER_BIT)
    ) uart_tx_inst (
        .clock,
        .txDataValid(txDataValid),
        .txByteData(txByteData),
        .txActive,
        .txDataStream
    );

    fifo #(
        .DEPTH(16),
        .WIDTH(8)
    ) tx_fifo_inst (
        .clock,
        .reset,
        .writeEnable(txWriteEnable),
        .readEnable(txReadEnable),
        .dataRead(txDataRead),
        .dataWrite(txDataWrite),
        .empty(txEmpty),
        .full(txFull)
    );

    //Read from RX if writeEnable is down
    assign rxReadEnable = strobeIn && cycleIn && !writeEnableIn && (addrSelected == 2'b00);

    //Once data goes through RX, push it to RX FIFO
    assign rxWriteEnable = rxDataValid && !rxFull;
    
    //Drive interrupt when the RX FIFO is not empty
    assign interrupt = !rxEmpty;

    //Write to FIFO one writeEnable goes up
    assign txWriteEnable = writeEnableIn && (addrSelected == 2'b01) && !txFull;

    //At the same cycle txWriteEnable goes up, write to FIFO
    assign txDataWrite = dataWrite;

    //Once FIFO is non-empty, let TX read
    assign txDataValid = !txEmpty && !txActive;
    assign txReadEnable = txDataValid;

    //Connect the TX parallel data to the data output from FIFO
    assign txByteData = txDataRead;

    assign addrSelected = addrIn[1:0];
    assign dataWrite = dataIn[7:0];
    assign dataOut = {dataRead, dataRead, dataRead, dataRead};

    //UART never causes cpu stalls
    assign stallOut = 1'b0;

    always_ff @(posedge clock)
        begin
            if (reset) 
                begin
                    dataRead <= 8'h00;
                    acknowledgedOut <= 1'b0;
                end 
            else 
                begin
                    acknowledgedOut <= 1'b0;

                    if (strobeIn && cycleIn)
                        begin
                            acknowledgedOut <= 1'b1;

                            if (!writeEnableIn) 
                                begin
                                    case (addrSelected)
                                        2'b00: dataRead <= rxDataRead;
                                        2'b10: dataRead <= {interrupt,
                                                            1'b0,
                                                            txFull,
                                                            txEmpty,
                                                            rxFull,
                                                            rxEmpty,
                                                            rxEmpty && !interrupt,
                                                            txActive};
                                        default: dataRead <= 8'h00;
                                    endcase
                                end
                        end
            end
        end

endmodule