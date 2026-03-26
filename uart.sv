module uart #(
    parameter CYCLES_PER_BIT = 217;
) (
    input logic clock,
    input logic reset,

    input logic [1:0] addr_select,

    input logic rx,
    output logic tx
);
    logic txDataValid = 0;
    logic txActive;
    logic txDataStream;
    logic [7:0] txByteData = 0;
    logic [7:0] rxByteData;
    logic rxDataValid;
    //logic done;

    uart_rx #(
        .CYCLES_PER_BIT(CYCLES_PER_BIT)
    ) uart_rx_inst (
        .clock,
        .rxDataStream(rx),
        .rxDataValid,
        .rxByteData
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

    assign tx = txActive ? txDataStream : 1'b1;

endmodule