module uart #(
    parameter CYCLES_PER_BIT = 217
) (
    input logic clock,
    input logic reset,

    input logic [1:0] addrSelected,
    input logic writeEnable,
    input logic readEnable,
    input logic [31:0] dataWrite,
    input logic rxDataStream,

    output logic interrupt,
    output logic [31:0] dataRead,
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

    //Continous assignments for the read and write signals for FIFO
    assign txReadEnable = !txEmpty & !txActive;
    assign txWriteEnable = (addrSelected == 2'b01);

    assign rxReadEnable = (addrSelected == 2'b00) && readEnable;
    assign rxWriteEnable = !rxFull & rxDataValid;

    assign rxDataWrite = rxByteData;
    assign txDataWrite = dataWrite[7:0];

    assign txByteData = txDataRead;

    assign txDataValid = !txEmpty;

    always_comb 
        begin
            case(addrSelected)
                2'b00: dataRead = {24'b0, rxDataRead};
                2'b01: dataRead = {24'b0, txDataWrite};
                2'b10: dataRead = {24'b0, 
                                   interrupt, 
                                   1'b0, 
                                   txFull, 
                                   txEmpty, 
                                   rxFull, 
                                   rxEmpty, 
                                   rxDataValid, 
                                   txActive};

                default: dataRead = 32'b0;
            endcase
        end

    always_ff @(posedge clock or posedge reset) 
        begin
            if (reset) 
                begin
                    interrupt <= 0;
                end 
            else 
                begin
                    if (rxDataValid) 
                        begin
                            interrupt <= 1;
                        end

                    if (rxReadEnable) 
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
        .rxDataValid,
        .rxByteData
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
        .txDataValid,
        .txByteData,
        .txActive,
        .txDataStream,
        .done()
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