module uart_tx #(
    parameter CYCLES_PER_BIT = 217
) (
    input logic clock,
    input logic txDataValid,
    input logic [7:0] txByteData,

    output logic txActive,
    output logic txDataStream,
    output logic done
);

    typedef enum{
        IDLE,
        START_BIT,
        DATA_BIT,
        PARITY_BIT,
        END_BIT
    } state_t;

    state_t state = IDLE;

    logic [7:0] count;
    logic [7:0] data;
    logic [2:0] bitIndex;
    logic parityBit;

    always @(posedge clock)
        begin
            case(state)
                IDLE:
                    begin
                        count <= 0;
                        done <= 0;
                        bitIndex <= 0;
                        txDataStream <= 1;
                        txActive <= 0;

                        if (txDataValid)
                            begin
                                data <= txByteData;
                                parityBit <= ^txByteData; 
                                txActive <= 1;
                                state <= START_BIT;
                            end
                    end
                START_BIT:
                    begin
                        txDataStream <= 0;

                        if (count < CYCLES_PER_BIT - 1)
                            count <= count + 1;
                        else
                            begin 
                                count <= 0;
                                state <= DATA_BIT;
                            end
                    end
                DATA_BIT:
                    begin
                        txDataStream <= data[bitIndex];

                        if (count < CYCLES_PER_BIT - 1)
                            count <= count + 1;
                        else
                            begin
                                count <= 0;

                                if (bitIndex < 7)
                                    bitIndex <= bitIndex + 1;
                                else
                                    begin
                                        bitIndex <= 0;
                                        state <= PARITY_BIT;
                                    end
                            end
                    end
                PARITY_BIT:
                    begin
                        txDataStream <= parityBit;

                        if (count < CYCLES_PER_BIT - 1)
                            count <= count + 1;
                        else
                        begin
                            count <= 0;
                            state <= END_BIT;
                        end
                    end
                END_BIT:
                    begin
                        txDataStream <= 1;

                        if (count < CYCLES_PER_BIT - 1)
                            count <= count + 1;
                        else
                            begin
                                count <= 0;
                                txActive <= 0;
                                done <= 1;
                                state <= IDLE;
                            end
                    end

                default:
                    state <= IDLE;
            endcase
        end

endmodule