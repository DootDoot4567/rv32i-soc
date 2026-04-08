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
    input logic [3:0] bramWriteMask,
    input logic [WIDTH-1:0] dataWrite,
    output logic [WIDTH-1:0] dataRead
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
                    if (bramWriteMask[0])
                        begin
                            memory[addrWrite][7:0] <= dataWrite[7:0];
                        end
                    if (bramWriteMask[1])
                        begin 
                            memory[addrWrite][15:8] <= dataWrite[15:8];
                        end
                    if (bramWriteMask[2])
                        begin
                            memory[addrWrite][23:16] <= dataWrite[23:16];
                        end
                    if (bramWriteMask[3]) 
                        begin
                            memory[addrWrite][31:24] <= dataWrite[31:24];
                        end
                end
        end
        
    // Port B: Sync Read
    always_ff @(posedge clockRead) 
        begin
            if (readEnable) 
                begin
                    dataRead <= memory[addrRead];
                end
        end
endmodule