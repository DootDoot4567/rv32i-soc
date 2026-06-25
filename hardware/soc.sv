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
    localparam [ADDR_WIDTH - 1:0] ROM_BASE = 32'h00008000;
    localparam [ADDR_WIDTH - 1:0] UART_BASE = 32'h00000340;

    //Interconnect IO masks
    localparam [ADDR_WIDTH - 1:0] ROM_MASK = 32'hFFFF8000;
    localparam [ADDR_WIDTH - 1:0] UART_MASK = 32'hFFFFFFFC;

    //CPU - Master 1
    //BRAM - Slave 1 
    //UART - Slave 2

    typedef enum {
        PROCESSOR,
        NUM_MASTERS
    } master_id_t;

    typedef enum {
        BRAM,
        UART, 
        NUM_SLAVES
    } slave_id_t;
    
    //Declaration of the number of peripherals of our system
    //By adding to the end of our enums

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
    logic [NUM_SLAVES - 1:0][WIDTH - 1:0] slaveDataIn;
    logic [NUM_SLAVES - 1:0][WIDTH - 1:0] slaveDataOut;
    logic [NUM_SLAVES - 1:0][3:0] slaveSelectIn;
    logic [NUM_SLAVES - 1:0] slaveAcknowledgedOut;
    logic [NUM_SLAVES - 1:0] slaveWriteEnableIn;
    logic [NUM_SLAVES - 1:0] slaveStrobeIn;
    logic [NUM_SLAVES - 1:0] slaveCycleIn;
    logic [NUM_SLAVES - 1:0] slaveStallOut;

    logic uartInterrupt;
    logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] slave_io_base;
    logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] slave_addr_mask;

    assign slave_io_base = {
        {UART_BASE},
        {ROM_BASE}
    };

    assign slave_addr_mask = { 
        {UART_MASK},
        {ROM_MASK}
    };

    processor #(
        .INIT(INIT),
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RESET_ADDRESS(ROM_BASE)
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
        .NUM_SLAVES(NUM_SLAVES),
        .NUM_MASTERS(NUM_MASTERS),
        .WIDTH(WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) wb_interconn_inst (
        .clock(clock),
        .reset(reset),
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
        .slaveCycleIn(slaveCycleIn),
        .slave_io_base(slave_io_base),
        .slave_addr_mask(slave_addr_mask)
    );

    bram_sdp #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT(INIT),
        .ROM_BASE(ROM_BASE)
    ) bram_inst (
        .clock(clock),
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
        .clock(clock),
        .reset(reset),
        .rxDataStream(rxDataStream),
        .addrIn(slaveAddrIn[UART]),
        .dataIn(slaveDataIn[UART]),
        .selectIn(slaveSelectIn[UART]),
        .strobeIn(slaveStrobeIn[UART]),
        .cycleIn(slaveCycleIn[UART]),
        .writeEnableIn(slaveWriteEnableIn[UART]),
        .interrupt(uartInterrupt), //replace with something, force interrupt instead of polling for uart eventually add dma?
        .stallOut(slaveStallOut[UART]),
        .acknowledgedOut(slaveAcknowledgedOut[UART]),
        .dataOut(slaveDataOut[UART]),
        .txDataStream(txDataStream)
    );

endmodule