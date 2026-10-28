//Code inspired by https://www.youtube.com/watch?v=4FwESTOVT-o

//Pipelined implementation of:
//Modified (Radix-4) Booth Recoding + Wallace Tree Multiplier

module multiplier #(
    parameter WIDTH = 32,
    localparam HALF_WIDTH = WIDTH >> 1,
    localparam DOUBLE_WIDTH = WIDTH << 1
) (
    input logic clock,
    input logic reset,

    input logic start,
    input logic signed_mode,

    input logic [WIDTH - 1:0] operand_a,
    input logic [WIDTH - 1:0] operand_b,

    output logic busy,
    output logic done,

    output logic [DOUBLE_WIDTH - 1:0] result
);
    //Do regular booth encoding
    //Apply encoding on pairs of bit produced by prev step

    //However both can be done in one step
    //using a Partial Product Selection Table
    logic [WIDTH:0] multiplier;
    logic [DOUBLE_WIDTH:0] product;
    // logic [HALF_WIDTH - 1:0] boothRecordingOutput;

    typedef struct packed {
        logic [WIDTH:0] partialProduct;
        logic neg;
    } booth_row_t;

    function automatic booth_row_t computePartialProduct(
        logic [WIDTH - 1:0]multiplicand,
        logic [2:0] window
    );
        booth_row_t result;
        logic [WIDTH:0] sum;
        logic [WIDTH:0] doubleMultiplicand = {multiplicand, 1'b0};

        case(window)
            3'b000, 3'b111: sum = 0;
            3'b001, 3'b010: sum = multiplicand;
            3'b011: sum = doubleMultiplicand;
            3'b100: sum = ~doubleMultiplicand;
            3'b101, 3'b110: sum = ~multiplicand;
        endcase

        result.partialProduct = sum;
        result.neg = (window >= 3'b100 && window < 3'b111);

        return result;
    endfunction

    always_ff @(posedge clock)
        begin
            if (reset)
                begin
                    multiplier <= '0;
                end
            else if (start)
                begin
                    multiplier <= {operand_b, 1'b0};
                end
        end

    for (int i = 0; i < HALF_WIDTH - 1; i++)
            begin
                row = computePartialProduct(operand_a, multiplier).partialProduct;
            end

endmodule