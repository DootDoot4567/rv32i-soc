//Code inspired by https://www.youtube.com/watch?v=4FwESTOVT-o

//Pipelined implementation of:
//Modified (Radix-4) Booth Recoding + Wallace Tree Multiplier

module multiplier #(
    localparam WIDTH = 32,
    localparam HALF_WIDTH = 16,
    localparam DOUBLE_WIDTH = 64,
    localparam NUM_BOOTH_PP = 4
) (
   input logic clock,
    input logic reset,

    input logic start,
    // input logic signed_mode,

    input logic [WIDTH - 1:0] multIn1,
    input logic [WIDTH - 1:0] multIn2,

    output logic busy,
    output logic done,

    output logic [DOUBLE_WIDTH - 1:0] result
);
    //Do regular booth encoding
    //Apply encoding on pairs of bit produced by prev step

    //However both can be done in one step
    //using a Partial Product Selection Table

    //Then compress partial product rows using a wallace tree

    logic [WIDTH:0] multiplier;

    typedef struct packed {
        logic [WIDTH:0] partialProduct;
        logic neg;
    } booth_row_t;

    //Booth rows
    booth_row_t boothRecodingOutput1;
    booth_row_t boothRecodingOutput2;
    booth_row_t boothRecodingOutput3;
    booth_row_t boothRecodingOutput4;

    //Wallace Tree Injection
    logic [1:0] cycle_count;
    logic [DOUBLE_WIDTH:0] acc_sum;
    logic [DOUBLE_WIDTH:0] acc_carry;

    logic [NUM_BOOTH_PP - 1:0][DOUBLE_WIDTH:0] shifted_row;
    logic [DOUBLE_WIDTH:0] reduce4_sum;
    logic [DOUBLE_WIDTH:0] reduce4_carry;
    logic [DOUBLE_WIDTH:0] reduce6_sum;
    logic [DOUBLE_WIDTH:0] reduce6_carry;


    function automatic booth_row_t computePartialProduct(
        logic [WIDTH - 1:0] multiplicand,
        logic [2:0] window
    );
        booth_row_t result;
        logic [WIDTH:0] sum;
        logic [WIDTH:0] doubleMultiplicand;

        doubleMultiplicand = {multiplicand, 1'b0};

        //Partial Product Selection Table
        case(window)
            3'b000, 3'b111: sum = 0;
            3'b001, 3'b010: sum = {multiplicand[WIDTH-1], multiplicand};
            3'b011: sum = doubleMultiplicand;
            3'b100: sum = ~doubleMultiplicand + 1;
            3'b101, 3'b110: sum = ~{multiplicand[WIDTH-1], multiplicand} + 1;
        endcase

        result.partialProduct = sum;
        result.neg = (window >= 3'b100 && window < 3'b111);

        computePartialProduct = result;
    endfunction

    //Bookkeeping for internal multiplier state
    always_ff @(posedge clock)
        begin
            done <= busy && (cycle_count == 3);
            
            if (start)
                begin
                    busy <= 1'b1;
                    multiplier <= {multIn2, 1'b0};
                    cycle_count <= '0;
                    acc_sum   <= '0;
                    acc_carry <= '0;
                end
            else if (busy)
                begin
                    cycle_count <= cycle_count + 1;

                    if (cycle_count == 3)
                        begin
                            busy <= 1'b0;
                            result <= (acc_sum + acc_carry);
                        end
                end
            else
                begin
                    busy <= 1'b0;
                    multiplier <= '0;
                    cycle_count <= '0;
                    acc_sum   <= '0;
                    acc_carry <= '0;
                end
        end

    //Generate this cycle's rows (up to 4), shifted + correct neg bit
    always_comb 
        begin
            case (cycle_count)
                2'b00:
                    begin
                        boothRecodingOutput1 = computePartialProduct(multIn1, multiplier[2:0]);
                        boothRecodingOutput2 = computePartialProduct(multIn1, multiplier[4:2]);
                        boothRecodingOutput3 = computePartialProduct(multIn1, multiplier[6:4]);
                        boothRecodingOutput4 = computePartialProduct(multIn1, multiplier[8:6]);

                        shifted_row[0] = {
                            {32{boothRecodingOutput1.partialProduct[WIDTH]}},
                            boothRecodingOutput1.partialProduct
                        };
                        shifted_row[1] = {
                            {30{boothRecodingOutput2.partialProduct[WIDTH]}},
                            boothRecodingOutput2.partialProduct,
                            2'b0
                        };
                        shifted_row[2] = {
                            {28{boothRecodingOutput3.partialProduct[WIDTH]}},
                            boothRecodingOutput3.partialProduct,
                            4'b0
                        };
                        shifted_row[3] = {
                            {26{boothRecodingOutput4.partialProduct[WIDTH]}},
                            boothRecodingOutput4.partialProduct,
                            6'b0
                        };
                    end

                2'b01:
                    begin
                        boothRecodingOutput1 = computePartialProduct(multIn1, multiplier[10:8]);
                        boothRecodingOutput2 = computePartialProduct(multIn1, multiplier[12:10]);
                        boothRecodingOutput3 = computePartialProduct(multIn1, multiplier[14:12]);
                        boothRecodingOutput4 = computePartialProduct(multIn1, multiplier[16:14]);

                        shifted_row[0] = {
                            {24{boothRecodingOutput1.partialProduct[WIDTH]}},
                            boothRecodingOutput1.partialProduct,
                            8'b0
                        };
                        shifted_row[1] = {
                            {22{boothRecodingOutput2.partialProduct[WIDTH]}},
                            boothRecodingOutput2.partialProduct,
                            10'b0
                        };
                        shifted_row[2] = {
                            {20{boothRecodingOutput3.partialProduct[WIDTH]}},
                            boothRecodingOutput3.partialProduct,
                            12'b0
                        };
                        shifted_row[3] = {
                            {18{boothRecodingOutput4.partialProduct[WIDTH]}},
                            boothRecodingOutput4.partialProduct,
                            14'b0
                        };
                    end

                2'b10:
                    begin
                        boothRecodingOutput1 = computePartialProduct(multIn1, multiplier[18:16]);
                        boothRecodingOutput2 = computePartialProduct(multIn1, multiplier[20:18]);
                        boothRecodingOutput3 = computePartialProduct(multIn1, multiplier[22:20]);
                        boothRecodingOutput4 = computePartialProduct(multIn1, multiplier[24:22]);

                        shifted_row[0] = {
                            {16{boothRecodingOutput1.partialProduct[WIDTH]}},
                            boothRecodingOutput1.partialProduct,
                            16'b0
                        };
                        shifted_row[1] = {
                            {14{boothRecodingOutput2.partialProduct[WIDTH]}},
                            boothRecodingOutput2.partialProduct,
                            18'b0
                        };
                        shifted_row[2] = {
                            {12{boothRecodingOutput3.partialProduct[WIDTH]}},
                            boothRecodingOutput3.partialProduct,
                            20'b0
                        };
                        shifted_row[3] = {
                            {10{boothRecodingOutput4.partialProduct[WIDTH]}},
                            boothRecodingOutput4.partialProduct,
                            22'b0};
                    end

                2'b11:
                    begin
                        boothRecodingOutput1 = computePartialProduct(multIn1, multiplier[26:24]);
                        boothRecodingOutput2 = computePartialProduct(multIn1, multiplier[28:26]);
                        boothRecodingOutput3 = computePartialProduct(multIn1, multiplier[30:28]);
                        boothRecodingOutput4 = computePartialProduct(multIn1, multiplier[32:30]);

                        shifted_row[0] = {
                            {8{boothRecodingOutput1.partialProduct[WIDTH]}},
                            boothRecodingOutput1.partialProduct,
                            24'b0
                        };
                        shifted_row[1] = {
                            {6{boothRecodingOutput2.partialProduct[WIDTH]}},
                            boothRecodingOutput2.partialProduct,
                            26'b0
                        };
                        shifted_row[2] = {
                            {4{boothRecodingOutput3.partialProduct[WIDTH]}},
                            boothRecodingOutput3.partialProduct,
                            28'b0
                        };
                        shifted_row[3] = {
                            {2{boothRecodingOutput4.partialProduct[WIDTH]}},
                            boothRecodingOutput4.partialProduct,
                            30'b0
                        };
                    end

                default:
                    begin
                        boothRecodingOutput1 = '0;
                        boothRecodingOutput2 = '0;
                        boothRecodingOutput3 = '0;
                        boothRecodingOutput4 = '0;

                        shifted_row[0] = '0;
                        shifted_row[1] = '0;
                        shifted_row[2] = '0;
                        shifted_row[3] = '0;
                    end
            endcase
        end

    wallace_reduce_four_two #(.W(DOUBLE_WIDTH + 1)) red4 (
        .row0(shifted_row[0]),
        .row1(shifted_row[1]),
        .row2(shifted_row[2]),
        .row3(shifted_row[3]),
        .sum_out(reduce4_sum),
        .carry_out(reduce4_carry)
    );

    wallace_reduce_six_two #(.W(DOUBLE_WIDTH + 1)) red6 (
        .row0(acc_sum),
        .row1(acc_carry),
        .row2(shifted_row[0]),
        .row3(shifted_row[1]),
        .row4(shifted_row[2]),
        .row5(shifted_row[3]),
        .sum_out(reduce6_sum),
        .carry_out(reduce6_carry)
    );

    always_ff @(posedge clock) 
        begin
            if (busy) begin
                if (cycle_count == 3) begin
                    acc_sum   <= reduce4_sum;
                    acc_carry <= reduce4_carry;
                end else begin
                    acc_sum   <= reduce6_sum;
                    acc_carry <= reduce6_carry;
                end
            end
        end

endmodule