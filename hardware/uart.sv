module uart #(
    parameter CYCLES_PER_BIT = 217
) (
    input logic clock,
    input logic reset,

    input logic [1:0] addrSelected,
    input logic writeEnable,
    input logic readEnable,
    input logic [7:0] dataWrite,
    input logic rxDataStream,

    output logic interrupt,
    output logic [7:0] dataRead,
    output logic txDataStream
);
    //Transmission control    
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

    logic busTxWrite;
    logic [7:0] busTxData;
    logic busRxRead;

    assign busRxRead = readEnable && (addrSelected == 2'b00);
    assign busTxWrite = writeEnable && (addrSelected == 2'b01);
    assign busTxData = dataWrite;

    logic [7:0] txByteLatched;

    always_comb 
        begin
            dataRead = 8'b0;
            if (readEnable)
                begin
                    case (addrSelected)
                        2'b00: dataRead = (!rxEmpty) ? rxDataRead : 8'b0;
                        2'b10: dataRead = {interrupt,
                                           1'b0,
                                           txFull,
                                           txEmpty,
                                           rxFull,
                                           rxEmpty,
                                           rxEmpty && !interrupt,
                                           txFull};
                        
                        default: dataRead = 8'b0;
                    endcase
                end
        end

    always_ff @(posedge clock or posedge reset) 
        begin
            if (reset) 
                begin
                    rxReadEnable <= 0;
                    txReadEnable <= 0;
                    txWriteEnable <= 0;

                    txByteLatched   <= 8'd0;
                    txDataWrite <= 8'd0;

                    interrupt <= 0;
                end 
            else 
                begin
                    rxReadEnable <= 0;
                    txReadEnable <= 0;
                    txWriteEnable <= 0;

                    if (busTxWrite) 
                        begin
                            txWriteEnable <= 1;
                            txDataWrite <= busTxData;
                        end

                    if (!txEmpty && !txActive) 
                        begin
                            txByteLatched   <= txDataRead;
                            txReadEnable <= 1;
                        end

                    if ((rxWriteEnable || !rxEmpty) && !interrupt) 
                        begin
                            rxReadEnable <= 1;
                        end

                    if (rxReadEnable) 
                        begin
                            interrupt <= 1;
                        end

                    if (busRxRead) 
                        begin
                            interrupt <= 0;
                        end
                end
        end

    uart_rx #(
        .CYCLES_PER_BIT(CYCLES_PER_BIT)
    ) uart_rx_inst (
        .clock,
        .rxDataStream,
        .rxDataValid(rxWriteEnable),
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
        .txDataValid(txReadEnable),
        .txByteData(txByteLatched),
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

endmodule