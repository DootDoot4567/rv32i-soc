import soc_types_pkg::*;

module soc #(
    parameter INIT = "",
    parameter CYCLES_PER_BIT = 217
) (
    input logic clock,
    input logic reset,

    input logic rxDataStream,
    output logic txDataStream
);
    //Signals shared by the Masters and Slaves:

    //comes from SYStem CONtroller
    //clk - Clock
    //rst - Reset 

    //wE - Write Enable
    //data_i - Data In
    //data_o - Data Out

    //Both tag numbers likely not needed
    //due to FIFOs and no Out-of-Order (OoO) Exec yet

    //tagt_i - Tag Type In
    //tagt_o - Tag Type Out

    //Implement later...
    //logic masterErrorIn;
    //logic masterLockOut;
    //logic masterRetryIn;
    //logic masterCycleTagTypeOut;
    //logic masterAddrTagTypeOut;

    //logic slaveErrorOut;
    //logic slaveLockIn;
    //logic slaveRetryOut;
    //logic slaveCycleTagTypeIn;
    //logic slaveAddrTagTypeIn;

    //Packed Arrays
    logic [NUM_MASTERS - 1:0][ADDR_WIDTH - 1:0] masterAddrOut;
    logic [NUM_MASTERS - 1:0][WIDTH - 1:0] masterDataIn;
    logic [NUM_MASTERS - 1:0][WIDTH - 1:0] masterDataOut;
    logic [NUM_MASTERS - 1:0][3:0] masterSelectOut;
    logic [NUM_MASTERS - 1:0] masterAcknowledgedIn;
    logic [NUM_MASTERS - 1:0] masterWriteEnableOut;
    logic [NUM_MASTERS - 1:0] masterStrobeOut;
    logic [NUM_MASTERS - 1:0] masterCycleOut;
    logic [NUM_MASTERS - 1:0] masterStallIn;

    logic [NUM_SLAVES - 1:0][ADDR_WIDTH - 1:0] slaveAddrIn;
    logic [NUM_SLAVES - 1:0][WIDTH - 1:0] slaveDataOut;
    logic [NUM_SLAVES - 1:0][WIDTH - 1:0] slaveDataIn;
    logic [NUM_SLAVES - 1:0][3:0] slaveSelectIn;
    logic [NUM_SLAVES - 1:0] slaveAcknowledgedOut;
    logic [NUM_SLAVES - 1:0] slaveWriteEnableIn;
    logic [NUM_SLAVES - 1:0] slaveStrobeIn;
    logic [NUM_SLAVES - 1:0] slaveCycleIn;
    logic [NUM_SLAVES - 1:0] slaveStallOut;

    logic uartInterrupt;

    processor6 #(
        .WIDTH(WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RESET_ADDRESS(RESET_ADDRESS)
    ) processor_inst (
        .clockIn(clock),
        .resetIn(reset),
        .stallIn(masterStallIn[PROCESSOR]),
        .acknowledgedIn(masterAcknowledgedIn[PROCESSOR]),
        .dataIn(masterDataIn[PROCESSOR]),
        .dataOut(masterDataOut[PROCESSOR]),
        .addrOut(masterAddrOut[PROCESSOR]),
        .selectOut(masterSelectOut[PROCESSOR]),
        .writeEnableOut(masterWriteEnableOut[PROCESSOR]),
        .strobeOut(masterStrobeOut[PROCESSOR]),
        .cycleOut(masterCycleOut[PROCESSOR])
    );

    wb_interconn #(
        .WIDTH(WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) wb_interconn_inst (
        .clockIn(clock),
        .resetIn(reset),
        .masterAddrOut(masterAddrOut),
        .masterDataOut(masterDataOut),
        .masterSelectOut(masterSelectOut),
        .masterWriteEnableOut(masterWriteEnableOut),
        .masterStrobeOut(masterStrobeOut),
        .masterCycleOut(masterCycleOut),
        .masterDataIn(masterDataIn),
        .masterAcknowledgedIn(masterAcknowledgedIn),
        .masterStallIn(masterStallIn),
        .slaveDataOut(slaveDataOut),
        .slaveAcknowledgedOut(slaveAcknowledgedOut),
        .slaveStallOut(slaveStallOut),
        .slaveAddrIn(slaveAddrIn),
        .slaveDataIn(slaveDataIn),
        .slaveSelectIn(slaveSelectIn),
        .slaveWriteEnableIn(slaveWriteEnableIn),
        .slaveStrobeIn(slaveStrobeIn),
        .slaveCycleIn(slaveCycleIn)
    );

    bram_sdp #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT(INIT),
        .ROM_BASE(RESET_ADDRESS)
    ) bram_inst (
        .clockIn(clock),
        .resetIn(reset),
        .addrIn(slaveAddrIn[BRAM]),
        .dataIn(slaveDataIn[BRAM]),
        .selectIn(slaveSelectIn[BRAM]),
        .strobeIn(slaveStrobeIn[BRAM]),
        .cycleIn(slaveCycleIn[BRAM]),
        .writeEnableIn(slaveWriteEnableIn[BRAM]),
        .stallOut(slaveStallOut[BRAM]),
        .acknowledgedOut(slaveAcknowledgedOut[BRAM]),
        .dataOut(slaveDataOut[BRAM])
    );

    uart #(
        .CYCLES_PER_BIT(CYCLES_PER_BIT)
    ) uart_inst (
        .clockIn(clock),
        .resetIn(reset),
        .rxDataStream(rxDataStream),
        .addrIn(slaveAddrIn[UART]),
        .dataIn(slaveDataIn[UART]),
        .selectIn(slaveSelectIn[UART]),
        .strobeIn(slaveStrobeIn[UART]),
        .cycleIn(slaveCycleIn[UART]),
        .writeEnableIn(slaveWriteEnableIn[UART]),
        .stallOut(slaveStallOut[UART]),
        .acknowledgedOut(slaveAcknowledgedOut[UART]),
        .dataOut(slaveDataOut[UART]),
        .txDataStream(txDataStream)
    );

endmodule
