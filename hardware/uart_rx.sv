//CYCLES_PER_BIT = 25 MHZ / 115000 Baud

module uart_rx #(
    parameter CYCLES_PER_BIT = 217
) (
    input logic clock,
    input logic rxDataStream,

    output logic rxDataValid,
    output logic [7:0] rxByteData
);

    typedef enum{
        IDLE,
        START_BIT,
        DATA_BIT,
        END_BIT
    } state_t;

    state_t state = IDLE;

    logic [7:0] count;
    logic [7:0] data;
    logic [2:0] bitIndex;
    logic dataValid;

    always @(posedge clock)
        begin
            case(state)
                IDLE:
                    begin
                        dataValid <= 0;
                        count <= 0;
                        bitIndex <= 0;

                        if (rxDataStream === 1'b0)
                            state <= START_BIT;
                    end
                START_BIT:
                    begin
                        if (count === (CYCLES_PER_BIT - 1) / 2)
                            begin
                                if (rxDataStream === 1'b0)
                                    begin
                                        count <= 0;
                                        state <= DATA_BIT;
                                    end
                                else
                                    begin
                                        state <= IDLE;
                                    end
                            end
                        else
                            count <= count + 1;
                    end
                DATA_BIT:
                    begin
                        if (count < CYCLES_PER_BIT - 1)
                            count <= count + 1;
                        else
                            begin
                                count <= 0;
                                data[bitIndex] <= rxDataStream;

                                if (bitIndex < 7)
                                    bitIndex <= bitIndex + 1;
                                else
                                    begin
                                        bitIndex <= 0;
                                        state <= END_BIT;
                                    end
                            end
                    end
                END_BIT:
                    begin
                        if (count < CYCLES_PER_BIT - 1)
                            count <= count + 1;
                        else
                            begin
                                dataValid <= 1;
                                count <= 0;
                                state <= IDLE;
                            end
                    end

                default:
                    state <= IDLE;
            endcase
        end


    assign rxDataValid = dataValid;
    assign rxByteData = data;

endmodule