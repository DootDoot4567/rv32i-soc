// This code is based on Project F's line drawing tutorial (projectF.io)
// with modifications and cleanup

module bram_sdp #(
    parameter WIDTH = 32, 
    parameter DEPTH = 4096, 
    parameter ADDR_WIDTH = 12,
    parameter INIT = "data/firmware.mem",
    parameter ROM_BASE = 32'h00008000
) (
    input logic clockIn,
    input logic resetIn,
    input logic [ADDR_WIDTH - 1:0] addrIn,
    input logic [WIDTH - 1:0] dataIn,
    input logic [3:0] selectIn,
    input logic strobeIn,
    input logic cycleIn,
    input logic writeEnableIn,

    output logic stallOut,
    output logic acknowledgedOut,
    output logic [WIDTH - 1:0] dataOut
);

    logic [WIDTH-1:0] memory [DEPTH];

    logic [ADDR_WIDTH - 1:0] computedAddr;

    //Registered request
    logic [ADDR_WIDTH - 1:0] r_addr;
    logic [WIDTH - 1:0] r_data;
    logic [3:0] r_select;
    logic r_write;

    // Wait state
    logic [2:0] waitCounter;
    logic busy = 0;

    assign computedAddr = (addrIn >= 32'h8000) ? ((addrIn - ROM_BASE) >> 2) : addrIn >> 2;

    initial begin
        if (INIT != "") begin
            $display("Load init file '%s' into bram_sdp.", INIT);
            $readmemh(INIT, memory);
        end
    end

    assign stallOut = !acknowledgedOut;

    always_ff @(posedge clockIn) 
        begin
            // ACK is only asserted for one cycle
            acknowledgedOut <= 1'b0;

            // // Accept a new request
            // if (strobeIn && cycleIn && !busy) 
            //     begin
            //         r_addr <= computedAddr;
            //         r_data <= dataIn;
            //         r_select <= selectIn;
            //         r_write <= writeEnableIn;

            //         waitCounter <= 3;
            //         busy <= 1'b1;
            //     end 
            // else if (busy) 
            //     begin
            //         if (waitCounter != 0) 
            //             begin
            //                 waitCounter <= waitCounter - 1;
            //             end
            //         else 
            //             begin
            //                 // Execute transaction
            //                 if (r_write) begin
            //                     for (int i = 0; i < (WIDTH >> 3); i++) begin
            //                         if (r_select[i]) begin
            //                             memory[r_addr][i*8 +: 8]
            //                                 <= r_data[i*8 +: 8];
            //                         end
            //                     end
            //                 end
            //                 else begin
            //                     dataOut <= memory[r_addr];
            //                 end

            //                 acknowledgedOut <= 1'b1;
            //                 busy <= 1'b0;
            //             end
            //     end

            if (strobeIn && cycleIn)
                begin
                    if (writeEnableIn)
                        begin
                            begin
                                for (int i = 0; i < (WIDTH >> 3); i++)
                                    begin
                                        acknowledgedOut <= strobeIn && cycleIn;
                                        if (selectIn[i])
                                            begin
                                                memory[computedAddr][i*8 +: 8] <= dataIn[i*8 +: 8];
                                            end
                                    end
                            end
                        end
                    else
                        begin
                            acknowledgedOut <= strobeIn && cycleIn;
                            dataOut <= memory[computedAddr];
                        end
                end
        end
endmodule
