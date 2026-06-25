module wb_interconn #(
    parameter NUM_SLAVES  = 2,
    parameter NUM_MASTERS  = 1,
    parameter WIDTH  = 32,
    parameter ADDR_WIDTH  = 32  
    //Base addresses and masks for each slave, packed arrays
    // parameter [NUM_SLAVES - 1:0][ADDR_WIDTH - 1:0] SLAVE_IO_BASE = '0,
    // parameter [NUM_SLAVES - 1:0][ADDR_WIDTH - 1:0] SLAVE_ADDR_MASK = '0 
) (
    input  logic clock,
    input  logic reset,

    //Master ports
    input logic [NUM_MASTERS - 1:0][ADDR_WIDTH - 1:0] masterAddrOut,
    input logic [NUM_MASTERS - 1:0][WIDTH - 1:0] masterDataOut,
    input logic [NUM_MASTERS - 1:0][3:0] masterSelectOut,
    input logic [NUM_MASTERS - 1:0] masterWriteEnableOut,
    input logic [NUM_MASTERS - 1:0] masterStrobeOut,
    input logic [NUM_MASTERS - 1:0] masterCycleOut,
    output logic [NUM_MASTERS - 1:0][WIDTH - 1:0] masterDataIn,
    output logic [NUM_MASTERS - 1:0] masterAcknowledgedIn,
    output logic [NUM_MASTERS - 1:0] masterStallIn,

    //Slave ports
    input logic [NUM_SLAVES - 1:0][WIDTH - 1:0] slaveDataOut,
    input logic [NUM_SLAVES - 1:0] slaveAcknowledgedOut,
    input logic [NUM_SLAVES - 1:0] slaveStallOut,
    output logic [NUM_SLAVES - 1:0][ADDR_WIDTH - 1:0] slaveAddrIn,
    output logic [NUM_SLAVES - 1:0][WIDTH - 1:0] slaveDataIn,
    output logic [NUM_SLAVES - 1:0][3:0] slaveSelectIn,
    output logic [NUM_SLAVES - 1:0] slaveWriteEnableIn,
    output logic [NUM_SLAVES - 1:0] slaveStrobeIn,
    output logic [NUM_SLAVES - 1:0] slaveCycleIn,

    input logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] slave_io_base,
    input logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] slave_addr_mask
);
    //only works if NUM_SLAVES is greater than 1
    logic [$clog2(NUM_SLAVES) - 1:0] slaveSelected, prevSlaveSelected;
    logic found;

    always_comb 
        begin
            slaveSelected = 0;
            found = 0;

            //size of bases and mask should be the same
            //compiles to priority encoder?
            foreach (slave_addr_mask[i])
                begin
                    if (!found && ((masterAddrOut[0] & slave_addr_mask[i]) == slave_io_base[i]))
                        begin
                            begin
                                slaveSelected = i;
                                found = !found;
                            end
                        end
                end
        end

    always_ff @(posedge clock)
        begin
            //here to fix cycle delay on synchronous reads
            prevSlaveSelected <= slaveSelected;
        end

    //P2P - One master connected to one slave
    always_comb 
        begin
            //because we work with vectors if the bus is not being used for one signal
            //defaults back to 0
            masterAcknowledgedIn = '0;
            masterDataIn = '0;
            masterStallIn = '0;

            slaveDataIn = '0;
            slaveAddrIn = '0;
            slaveSelectIn = '0;
            slaveWriteEnableIn = '0;
            slaveStrobeIn = '0;
            slaveCycleIn = '0;

            masterAcknowledgedIn[0] = slaveAcknowledgedOut[prevSlaveSelected];
            masterDataIn[0] = slaveDataOut[prevSlaveSelected];
            masterStallIn[0] = slaveStallOut[prevSlaveSelected];
            slaveDataIn[slaveSelected] = masterDataOut[0];
            slaveAddrIn[slaveSelected] = masterAddrOut[0];
            slaveSelectIn[slaveSelected] = masterSelectOut[0];
            slaveWriteEnableIn[slaveSelected] = masterWriteEnableOut[0];
            slaveStrobeIn[slaveSelected] = masterStrobeOut[0];
            slaveCycleIn[slaveSelected] = masterCycleOut[0];

        end

    //Shared Bus - Multiple masters granted bus control one at a time
    // always_comb 
    //     begin
    //         for (int i = 0; i < NUM_SLAVES; i++) 
    //             begin
    //                 if (slaveSelected[i]) 
    //                     begin
    //                         masterAcknowledgedIn = slaveAcknowledgedOut[i];
    //                         masterDataIn = slaveDataOut[i];
    //                         slaveDataIn[i] = masterDataOut;
    //                         slaveAddrIn[i] = masterAddrOut;
    //                         slaveSelectIn[i] = masterSelectOut;
    //                         slaveWriteEnableIn[i] = masterWriteEnableOut;
    //                         slaveStrobeIn[i] = masterStrobeOut;
    //                         slaveCycleIn[i] = masterCycleOut;
    //                     end
    //             end
    //     end

    //Crossbar Switching - Multiple P2P parallel channels operating simultaneously
    // always_comb 
    //     begin
    //         for (int i = 0; i < NUM_SLAVES; i++) 
    //             begin
    //                 if (slaveSelected[i]) 
    //                     begin
    //                         masterAcknowledgedIn = slaveAcknowledgedOut[i];
    //                         masterDataIn = slaveDataOut[i];
    //                         slaveDataIn[i] = masterDataOut;
    //                         slaveAddrIn[i] = masterAddrOut;
    //                         slaveSelectIn[i] = masterSelectOut;
    //                         slaveWriteEnableIn[i] = masterWriteEnableOut;
    //                         slaveStrobeIn[i] = masterStrobeOut;
    //                         slaveCycleIn[i] = masterCycleOut;
    //                     end
    //             end
    //     end

    //Data Flow - Data passes from through sequentially (pipelining)
    //?????????????


endmodule