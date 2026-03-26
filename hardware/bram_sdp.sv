`default_nettype none
`timescale 1ns / 1ps

// This code is based on Project F's line drawing tutorial (projectF.io)
// with modifications and cleanup

module bram_sdp #(
    parameter WIDTH = 32, 
    parameter DEPTH = 4096, 
    parameter ADDR_WIDTH = 12,
    parameter INIT = ""
) (
    input logic clockWrite,
    input logic clockRead,
    input logic writeEnable,
    input logic readEnable,
    input logic [ADDR_WIDTH-1:0] addrWrite,
    input logic [ADDR_WIDTH-1:0] addrRead,
    input logic [WIDTH-1:0] dataIn,
    output logic [WIDTH-1:0] dataOut
);

    logic [WIDTH-1:0] memory [DEPTH];

    initial begin
        if (INIT != "") begin
            $display("Load init file '%s' into bram_sdp.", INIT);
            $readmemh(INIT, memory);
        end
    end

    // Port A: Sync Write
    always_ff @(posedge clockWrite) 
        begin
            if (writeEnable)
                begin
                    memory[addrWrite] <= dataIn;
                end
        end
        
    // Port B: Sync Read
    always_ff @(posedge clockRead) 
        begin
            if (readEnable) 
                begin
                    dataOut <= memory[addrRead];
                end
        end
endmodule