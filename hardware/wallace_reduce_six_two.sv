module wallace_reduce_six_two #(
    parameter int W = 65
) (
    input  logic [W-1:0] row0, row1, row2, row3, row4, row5,
    output logic [W-1:0] sum_out,
    output logic [W-1:0] carry_out
);
    logic [W-1:0] l1_sum, l1_carry;

    // Level 1: compress 4 of the 6 rows down to (sum, carry)
    wallace_reduce_four_two #(.W(W)) level1 (
        .row0(row0), .row1(row1), .row2(row2), .row3(row3),
        .sum_out(l1_sum), .carry_out(l1_carry)
    );

    // Level 2: fold the remaining 2 rows in with level 1's result
    wallace_reduce_four_two #(.W(W)) level2 (
        .row0(l1_sum), .row1(l1_carry), .row2(row4), .row3(row5),
        .sum_out(sum_out), .carry_out(carry_out)
    );

endmodule