import soc_types_pkg::*;

module wb_interconn #(
    parameter WIDTH  = 32,
    parameter ADDR_WIDTH  = 16
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
    output logic [NUM_SLAVES - 1:0] slaveCycleIn
);
    typedef struct packed {
        //only works if NUM_SLAVES is greater than 1
        logic [$clog2(NUM_SLAVES) - 1:0] slaveSelected;
        logic found;
    } s_point;

    logic [$clog2(NUM_SLAVES) - 1:0] prevSlaveSelected;
    s_point slaveConnection;

    function automatic s_point connectSlavePoint(
        input logic [ADDR_WIDTH-1:0] addr
    );
        s_point result = '0;

        //size of bases and mask should be the same
        //compiles to priority encoder?
        for (int i = 1; i < NUM_SLAVES; i++)
            begin
                if (!result.found && ((addr & ADDR_MASK[i - 1]) == IO_BASE[i - 1]))
                    begin
                        result.slaveSelected = i;
                        result.found = 1;
                    end
            end
        
        connectSlavePoint = result;
    endfunction

    always_comb 
        begin
            slaveConnection = connectSlavePoint(masterAddrOut[PROCESSOR]);
        end

    always_ff @(posedge clock)
        begin
            //here to fix cycle delay on synchronous reads
            prevSlaveSelected <= slaveConnection.slaveSelected;
        end

    //P2P - One master connected to one slave
    always_comb 
        begin
            //because we work with vectors, we default back to 0 for parts of vector not used
            masterAcknowledgedIn = '0;
            masterDataIn = '0;
            masterStallIn = '0;

            slaveDataIn = '0;
            slaveAddrIn = '0;
            slaveSelectIn = '0;
            slaveWriteEnableIn = '0;
            slaveStrobeIn = '0;
            slaveCycleIn = '0;

            masterAcknowledgedIn[PROCESSOR] = slaveAcknowledgedOut[prevSlaveSelected];
            masterDataIn[PROCESSOR] = slaveDataOut[prevSlaveSelected];
            masterStallIn[PROCESSOR] = slaveStallOut[prevSlaveSelected];
            slaveDataIn[slaveConnection.slaveSelected] = masterDataOut[PROCESSOR];
            slaveAddrIn[slaveConnection.slaveSelected] = masterAddrOut[PROCESSOR];
            slaveSelectIn[slaveConnection.slaveSelected] = masterSelectOut[PROCESSOR];
            slaveWriteEnableIn[slaveConnection.slaveSelected] = masterWriteEnableOut[PROCESSOR];
            slaveStrobeIn[slaveConnection.slaveSelected] = masterStrobeOut[PROCESSOR];
            slaveCycleIn[slaveConnection.slaveSelected] = masterCycleOut[PROCESSOR];
        end

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
    
    //Data Flow - Data passes from through sequentially (pipelining)
    //?????????????


endmodule
