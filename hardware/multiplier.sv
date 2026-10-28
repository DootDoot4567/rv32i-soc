//Code inspired by https://www.youtube.com/watch?v=4FwESTOVT-o

//Pipelined implementation of:
//Modified (Radix-4) Booth Recoding + Wallace Tree Multiplier

module multiplier #(
    parameter WIDTH = 32,
    localparam HALF_WIDTH = 16,
    localparam DOUBLE_WIDTH = 64,
    localparam NUM_ROWS = 17
) (
    input logic clock,
    input logic reset,

    input logic start,
    input logic signed_mode,

    input logic [WIDTH - 1:0] multIn1,
    input logic [WIDTH - 1:0] multIn2,

    output logic busy,
    output logic done,

    output logic [DOUBLE_WIDTH - 1:0] result
);
    localparam int PW = DOUBLE_WIDTH + 1;

    //Do regular booth encoding
    //Apply encoding on pairs of bit produced by prev step

    //However both can be done in one step
    //using a Partial Product Selection Table

    //Then compress partial product rows using a wallace tree

    logic [WIDTH:0] multiplier;
    logic [DOUBLE_WIDTH:0] product;

    //Booth rows
    logic [WIDTH:0] boothRecodingOutput1;
    logic [WIDTH:0] boothRecodingOutput2;
    logic [WIDTH:0] boothRecodingOutput3;
    logic [WIDTH:0] boothRecodingOutput4;

    //Wallace Tree Injection
    logic [2:0] cycle_count;


    typedef struct packed {
        logic [WIDTH:0] partialProduct;
        logic neg;
    } booth_row_t;

    function automatic booth_row_t computePartialProduct(
        logic [WIDTH - 1:0] multiplicand,
        logic [2:0] window
    );
        booth_row_t result;
        logic [WIDTH:0] sum;
        logic [WIDTH:0] doubleMultiplicand = {multiplicand, 1'b0};

        //Partial Product Selection Table
        case(window)
            3'b000, 3'b111: sum = 0;
            3'b001, 3'b010: sum = {multiplicand[WIDTH-1], multiplicand};
            3'b011: sum = doubleMultiplicand;
            3'b100: sum = ~doubleMultiplicand;
            3'b101, 3'b110: sum = ~{multiplicand[WIDTH-1], multiplicand};
        endcase

        result.partialProduct = sum;
        result.neg = (window >= 3'b100 && window < 3'b111);

        return result;
    endfunction

    always_ff @(posedge clock)
        begin
            if (reset)
                begin
                    busy <= 1'b0;
                    multiplier <= '0;
                    cycle_count <= '0;
                end
            else if (start)
                begin
                    busy <= 1'b1;
                    multiplier <= {multIn2, 1'b0};
                    cycle_count <= '0;
                end
            else if (busy)
                begin
                    cycle_count <= cycle_count + 1;
                end
            else if (busy && cycle_count == 3)
                begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    result <= product;
                end
        end

    // ---- Generate this cycle's rows (up to 4), shifted + sign-extended + neg-corrected ----
    logic [PW-1:0] shifted_row [4];
    logic          row_valid   [4];
    int group_idx;
    booth_row_t row;
    logic [PW-1:0] ext_row;

    always_comb begin
        for (int g = 0; g < 4; g++) begin
            group_idx = cycle_count * 4 + g;
            row_valid[g] = (group_idx < NUM_ROWS);

            if (row_valid[g]) begin
                row = computePartialProduct(multIn1, multiplier[2*group_idx +: 3]);
                ext_row = {{(PW-(WIDTH+1)){row.partialProduct[WIDTH]}}, row.partialProduct};
                shifted_row[g] = (ext_row << (2*group_idx)) | (row.neg ? (PW'(1) << (2*group_idx)) : '0);
            end else begin
                shifted_row[g] = '0;
            end
        end
    end

    // ---- Accumulator (carry-save) ----
    logic [PW-1:0] acc_sum, acc_carry;

    logic [PW-1:0] reduce4_sum, reduce4_carry;
    logic [PW-1:0] reduce6_sum, reduce6_carry;

    wallace_reduce_four_two #(.W(PW)) red4 (
        .row0(shifted_row[0]), .row1(shifted_row[1]),
        .row2(shifted_row[2]), .row3(shifted_row[3]),
        .sum_out(reduce4_sum), .carry_out(reduce4_carry)
    );

    wallace_reduce_six_two #(.W(PW)) red6 (
        .row0(acc_sum), .row1(acc_carry),
        .row2(shifted_row[0]), .row3(shifted_row[1]),
        .row4(shifted_row[2]), .row5(shifted_row[3]),
        .sum_out(reduce6_sum), .carry_out(reduce6_carry)
    );

    always_ff @(posedge clock) begin
        if (reset || start) begin
            acc_sum   <= '0;
            acc_carry <= '0;
        end else if (busy) begin
            if (cycle_count == 3'd0) begin
                acc_sum   <= reduce4_sum;
                acc_carry <= reduce4_carry;
            end else begin
                acc_sum   <= reduce6_sum;
                acc_carry <= reduce6_carry;
            end
        end
    end

    // ---- Final add ----
    always_ff @(posedge clock) begin
        if (busy && cycle_count == 3'd4) begin
            result <= (acc_sum + acc_carry);
            done   <= 1'b1;
        end else begin
            done <= 1'b0;
        end
    end

endmodule