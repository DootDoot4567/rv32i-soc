// This code is based on Project F's line drawing tutorial (projectF.io)
// with modifications and cleanup

module bram_sdp #(
    parameter WIDTH = 32, 
    parameter DEPTH = 4096, 
    parameter ADDR_WIDTH = 12,
    parameter INIT = "firmware.mem",
    parameter ROM_BASE = 32'h00008000
) (
    input logic clock,
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

    assign computedAddr = (addrIn - ROM_BASE) >> 2;

    initial begin
        if (INIT != "") begin
            $display("Load init file '%s' into bram_sdp.", INIT);
            $readmemh(INIT, memory);
        end
    end

    //BRAM never tells cpu to stall
    assign stallOut = 1'b0;

    always_ff @(posedge clock) 
        begin
            acknowledgedOut <= strobeIn && cycleIn;

            if (strobeIn && cycleIn)
                begin
                    if (writeEnableIn)
                        begin
                            case (selectIn)
                                4'b0001: memory[computedAddr][7:0] <= dataIn[7:0];
                                4'b0010: memory[computedAddr][15:8] <= dataIn[15:8];
                                4'b0100: memory[computedAddr][23:16] <= dataIn[23:16];
                                4'b1000: memory[computedAddr][31:24] <= dataIn[31:24];

                                default: memory[computedAddr][7:0] <= dataIn[7:0];
                            endcase
                        end
                    else
                        begin
                            dataOut <= memory[computedAddr];
                        end
                end
        end
endmodule
