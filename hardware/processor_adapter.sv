module p3 #(
    parameter INIT = "",
    parameter WIDTH = 32,
    parameter DEPTH = 16384,
    parameter ADDR_WIDTH = 32,
    parameter RESET_ADDRESS = 32'h00008000
) (
    input  logic clock,
    input  logic reset,
    input  logic [WIDTH-1:0] dataRead,

    output logic writeEnable,
    output logic readEnable,
    output logic [ADDR_WIDTH-1:0] addrRead,
    output logic [ADDR_WIDTH-1:0] addrWrite,
    output logic [WIDTH-1:0] dataWrite,
    output logic [3:0] bramWriteMask
);
    logic acknowledgedIn;
    logic [WIDTH-1:0] dataIn;
    logic [WIDTH-1:0] dataOut;
    logic [ADDR_WIDTH-1:0] addrOut;
    logic [3:0] selectOut;
    logic writeEnableOut;
    logic strobeOut;
    logic cycleOut;
    logic stallIn;

    processor3 #(
        .INIT(INIT),
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RESET_ADDRESS(RESET_ADDRESS)
    ) proc (
        .clockIn(clock),
        .resetIn(reset),
        .stallIn(stallIn),
        .acknowledgedIn(acknowledgedIn),
        .dataIn(dataIn),
        .dataOut(dataOut),
        .addrOut(addrOut),
        .selectOut(selectOut),
        .writeEnableOut(writeEnableOut),
        .strobeOut(strobeOut),
        .cycleOut(cycleOut)
    );

    // BRAM always ACKs next cycle, UART takes 2 —
    // for now just tie ACK high so the processor never stalls.
    // This lets you verify fetch/decode/execute without bus timing.
    // always_ff @(posedge clock)
    //     begin
    //         acknowledgedIn <= strobeOut && cycleOut;
    //     end

    assign acknowledgedIn = strobeOut;
    assign stallIn = 1'b0;

    assign dataIn = dataRead;
    assign dataWrite = dataOut;
    assign bramWriteMask = selectOut;

    // Old SOC needs separate read/write addresses
    assign addrRead  = addrOut;
    assign addrWrite = addrOut;

    // Reconstruct old-style enables from WB signals
    assign writeEnable = strobeOut && cycleOut && writeEnableOut;
    assign readEnable  = strobeOut && cycleOut && !writeEnableOut;

endmodule