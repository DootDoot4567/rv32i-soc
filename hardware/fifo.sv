`default_nettype none

// Synchronous FIFO
//
// Circular buffer with read and write pointers
// full = next write_ptr collides with read_ptr
// empty = write_ptr == read_ptr
//
// Write and read data on the same cycle is allowed
// Writing to a full fifo will be ignored
// Reading from an empty fifo returns undefined data 

module fifo #(
    parameter DEPTH = 16,
    parameter WIDTH = 8
) (
    input logic clock,
    input logic reset,

    // Write port
    input logic writeEnable,
    input logic [WIDTH-1:0] dataWrite,

    // Read port
    input logic readEnable,
    output logic [WIDTH-1:0] dataRead,

    // Status
    output logic empty,
    output logic full
);
    localparam PTR_WIDTH = $clog2(DEPTH);

    logic [WIDTH-1:0] memory [0:DEPTH-1];
    logic [PTR_WIDTH:0] write_ptr = '0;  // extra bit for empty/full distinction
    logic [PTR_WIDTH:0] read_ptr  = '0;

    // Status flags
    assign empty = (write_ptr == read_ptr);
    assign full = (write_ptr[PTR_WIDTH-1:0] == read_ptr[PTR_WIDTH-1:0])
                    && (write_ptr[PTR_WIDTH] != read_ptr[PTR_WIDTH]);

    // Combinational read so that data is available same cycle 
    assign dataRead = empty ? {WIDTH{1'b0}} : memory[read_ptr[PTR_WIDTH-1:0]];

    always_ff @(posedge clock) begin
        if (reset) begin
            write_ptr <= '0;
            read_ptr <= '0;
        end else begin
            if (writeEnable && !full) begin
                memory[write_ptr[PTR_WIDTH-1:0]] <= dataWrite;
                write_ptr <= write_ptr + 1'b1;
            end
            if (readEnable && !empty) begin
                read_ptr <= read_ptr + 1'b1;
            end
        end
    end

endmodule
