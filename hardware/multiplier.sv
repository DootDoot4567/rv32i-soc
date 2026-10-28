//Code inspired by https://www.youtube.com/watch?v=4FwESTOVT-o

//Pipelined implementation of:
//Modified (Radix-4) Booth Recoding + Wallace Tree multIn2

module multiplier (
    input logic clock,
    input logic reset,

    input logic start,

    input logic [WIDTH - 1:0] multIn1,
    input logic [WIDTH - 1:0] multIn2,

    output logic busy,
    output logic done,

    output logic [DOUBLE_WIDTH - 1:0] result
);
    localparam WIDTH = 32;
    localparam HALF_WIDTH = 16;
    localparam DOUBLE_WIDTH = 64;
    localparam NUM_BOOTH_PP = 4;

    //Booth Recoding Outputs
    // logic [WIDTH:0] boothRow1;
    // logic [WIDTH:0] boothRow2;
    // logic [WIDTH:0] boothRow3;
    // logic [WIDTH:0] boothRow4;

    // logic neg1;
    // logic neg2;
    // logic neg3;
    // logic neg4;

    //Wallace Tree Injection
    logic [DOUBLE_WIDTH - 1:0] accumulatedCarry;
    logic [DOUBLE_WIDTH - 1:0] accumulatedCarryOut;
    logic [NUM_BOOTH_PP - 1:0][DOUBLE_WIDTH - 1:0] shifted_row;

    //Compressor IO
    logic [DOUBLE_WIDTH - 1:0] compressor1In1;
    logic [DOUBLE_WIDTH - 1:0] compressor1In2;
    logic [DOUBLE_WIDTH - 1:0] compressor1In3;
    logic [DOUBLE_WIDTH - 1:0] compressor1In4;

    logic [DOUBLE_WIDTH - 1:0] compressor2In1;
    logic [DOUBLE_WIDTH - 1:0] compressor2In2;
    logic [DOUBLE_WIDTH - 1:0] compressor2In3;
    logic [DOUBLE_WIDTH - 1:0] compressor2In4;

    logic [DOUBLE_WIDTH - 1:0] carryIn1;
    logic [DOUBLE_WIDTH - 1:0] carryOut1;
    logic [DOUBLE_WIDTH - 1:0] carry1;
    logic [DOUBLE_WIDTH - 1:0] sum1;

    logic [DOUBLE_WIDTH - 1:0] carryIn2;
    logic [DOUBLE_WIDTH - 1:0] carryOut2;
    logic [DOUBLE_WIDTH - 1:0] carry2;
    logic [DOUBLE_WIDTH - 1:0] sum2;

    typedef enum {
        IDLE,
        START,
        FIRST_ITR,
        SECOND_ITR,
        THIRD_ITR,
        FOURTH_ITR,
        FINISH
    } multiplier_state_t;

    multiplier_state_t state; 

    four_two_compressor four_two_compressor_inst1 [DOUBLE_WIDTH - 1:0] (
        .compressorIn1(compressor1In1),
        .compressorIn2(compressor1In2),
        .compressorIn3(compressor1In3),
        .compressorIn4(compressor1In4),
        .carryIn(carryIn1),
        .sum(sum1),
        .carry(carry1),
        .carryOut(carryOut1)
    );

    four_two_compressor four_two_compressor_inst2 [DOUBLE_WIDTH - 1:0] (
        .compressorIn1(compressor2In1),
        .compressorIn2(compressor2In2),
        .compressorIn3(compressor2In3),
        .compressorIn4(compressor2In4),
        .carryIn(carryIn2),
        .sum(sum2),
        .carry(carry2),
        .carryOut(carryOut2)
    );

    //Do regular booth encoding
    //Apply encoding on pairs of bit produced by prev step

    //However both can be done in one step
    //using a Partial Product Selection Table

    //Then compress partial product rows using a wallace tree

    function automatic [WIDTH:0] computePartialProduct(
        input logic [WIDTH - 1:0] multiplicand,
        input logic [2:0] window
    );
        logic [WIDTH:0] doubleMultiplicand;

        doubleMultiplicand = {multiplicand, 1'b0};

        //Partial Product Selection Table
        case(window)
            3'b000, 3'b111: computePartialProduct = 0;
            3'b001, 3'b010: computePartialProduct = {multiplicand[WIDTH-1], multiplicand};
            3'b011: computePartialProduct = doubleMultiplicand;
            3'b100: computePartialProduct = ~doubleMultiplicand;
            3'b101, 3'b110: computePartialProduct = ~{multiplicand[WIDTH-1], multiplicand};
        endcase
    endfunction

    function automatic computeCorrection(
        input logic [2:0] window
    );
        computeCorrection = window[2] & ~(window[1] & window[0]);
    endfunction

    function automatic [DOUBLE_WIDTH - 1:0] shifter(
        input [DOUBLE_WIDTH - 1:0] num
    );
        //discard msb
        shifter = {num[DOUBLE_WIDTH - 2:0], 1'b0};
    endfunction

    function automatic [DOUBLE_WIDTH-1:0] placeRow(
        input logic [WIDTH-1:0] multiplicand,
        input logic [2:0] window,
        input logic previousRowCorrection,
        input int offsetConst
    );
        logic [WIDTH:0] pp;
        pp = computePartialProduct(multiplicand, window);

        placeRow = '0;
        for (int i = 0; i < DOUBLE_WIDTH; i++)
            begin
                if (i >= offsetConst && i <= offsetConst + WIDTH)
                    begin
                        placeRow[i] = pp[i - offsetConst];
                    end
                else if (i > offsetConst + WIDTH)
                    begin
                        placeRow[i] = pp[WIDTH];
                    end
            end
        
        //Correction of previous row 
        if (offsetConst > 0)
            begin
                placeRow[offsetConst - 2] = previousRowCorrection;
            end
    endfunction

    assign carryIn1 = {carryOut1[DOUBLE_WIDTH-2:0], 1'b0};
    assign carryIn2 = {carryOut2[DOUBLE_WIDTH-2:0], 1'b0};

    //Bookkeeping for internal multiplier state
    always_ff @(posedge clock)
        begin
            if (start)
                begin
                    busy <= 1'b1;
                    done <= 0;
                    result <= 0;
                    state <= START;
                end 
            else if (busy)
                begin
                    //Generate this cycle's rows (up to 4), shifted + correct neg bit
                    case(state)
                        START:
                            begin
                                compressor1In1 <= placeRow(multIn1, {multIn2[1:0], 1'b0}, '0, 0);
                                compressor1In2 <= placeRow(multIn1, multIn2[3:1], computeCorrection({multIn2[1:0], 1'b0}), 2);
                                compressor1In3 <= placeRow(multIn1, multIn2[5:3], computeCorrection(multIn2[3:1]), 4);
                                compressor1In4 <= placeRow(multIn1, multIn2[7:5], computeCorrection(multIn2[5:3]), 6);

                                compressor2In1 <= placeRow(multIn1, multIn2[9:7], computeCorrection(multIn2[7:5]), 8);
                                compressor2In2 <= placeRow(multIn1, multIn2[11:9], computeCorrection(multIn2[9:7]), 10);
                                compressor2In3 <= placeRow(multIn1, multIn2[13:11], computeCorrection(multIn2[11:9]), 12);
                                compressor2In4 <= placeRow(multIn1, multIn2[15:13], computeCorrection(multIn2[13:11]), 14);

                                // carryIn1 <= '0;
                                // carryIn2 <= '0;

                                state <= FIRST_ITR;
                            end
                        FIRST_ITR:
                            begin
                                compressor1In1 <= placeRow(multIn1, multIn2[17:15], computeCorrection(multIn2[15:13]), 16);
                                compressor1In2 <= placeRow(multIn1, multIn2[19:17], computeCorrection(multIn2[17:15]), 18);
                                compressor1In3 <= placeRow(multIn1, multIn2[21:19], computeCorrection(multIn2[19:17]), 20);
                                compressor1In4 <= placeRow(multIn1, multIn2[23:21], computeCorrection(multIn2[21:19]), 22);
            
                                compressor2In1 <= sum1;
                                compressor2In2 <= sum2;
                                compressor2In3 <= {carry1[DOUBLE_WIDTH-2:0], 1'b0};
                                compressor2In4 <= {carry2[DOUBLE_WIDTH-2:0], 1'b0};

                                // carryIn1 <= carry2;
                                // carryIn2 <= carryOut2;

                                state <= SECOND_ITR;
                            end
                        SECOND_ITR:
                            begin
                                compressor1In1 <= placeRow(multIn1, multIn2[25:23], computeCorrection(multIn2[23:21]), 24);
                                compressor1In2 <= placeRow(multIn1, multIn2[27:25], computeCorrection(multIn2[25:23]), 26);
                                compressor1In3 <= placeRow(multIn1, multIn2[29:27], computeCorrection(multIn2[27:25]), 28);
                                compressor1In4 <= placeRow(multIn1, multIn2[31:29], computeCorrection(multIn2[29:27]), 30);

                                compressor2In1 <= sum1;
                                compressor2In2 <= sum2;
                                compressor2In3 <= {carry1[DOUBLE_WIDTH-2:0], 1'b0};
                                compressor2In4 <= {carry2[DOUBLE_WIDTH-2:0], 1'b0};

                                // carryIn1 <= carry2;
                                // carryIn2 <= carryOut2;

                                state <= THIRD_ITR;
                            end
                        THIRD_ITR:
                            begin
                                compressor1In1 <= sum1;
                                compressor1In2 <= sum2;
                                compressor1In3 <= {carry1[DOUBLE_WIDTH-2:0], 1'b0};
                                compressor1In4 <= {carry2[DOUBLE_WIDTH-2:0], 1'b0};

                                // carryIn1 <= {33'b0, computeCorrection(multIn2[31:29]), 30'b0};

                                state <= FOURTH_ITR;
                            end
                        FOURTH_ITR:
                            begin
                                result <=  sum1 + {carry1[DOUBLE_WIDTH-2:0], 1'b0} + {33'b0, computeCorrection(multIn2[31:29]), 30'b0};
                                busy <= 1'b0;
                                done <= 1;
                                state <= FINISH;
                            end
                        FINISH:
                            begin
                                state <= IDLE;
                            end
                    endcase
                end
            else
                begin
                    busy <= 1'b0;
                    done <= 0;
                    result <= 0;
                    state <= IDLE;
                end
        end
endmodule