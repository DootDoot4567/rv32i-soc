//CYCLES_PER_BIT = 25 MHZ / 115000 Baud

module uart_rx #(
    parameter CYCLES_PER_BIT = 217
) (
    input logic clock,
    input logic rxDataStream,

    output logic rxDataValid,
    output logic [7:0] rxByteData
);
    logic [7:0] count;
    logic [7:0] data;
    logic [2:0] bitIndex;
    logic dataValid;
    logic parityBit;
    logic parityError;
    
    typedef enum{
        IDLE,
        START_BIT,
        DATA_BIT,
        PARITY_BIT,
        END_BIT
    } state_t;

    state_t state = IDLE;

    always_ff @(posedge clock)
        begin
            case(state)
                IDLE:
                    begin
                        dataValid <= 0;
                        count <= 0;
                        bitIndex <= 0;
                        parityError <= 0;

                        if (rxDataStream === 1'b0)
                            begin
                                state <= START_BIT;
                            end
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
                            begin
                                count <= count + 1;
                            end
                    end
                DATA_BIT:
                    begin
                        if (count < CYCLES_PER_BIT - 1)
                            begin
                                count <= count + 1;
                            end
                        else
                            begin
                                count <= 0;
                                data[bitIndex] <= rxDataStream;

                                if (bitIndex < 7)
                                    begin
                                        bitIndex <= bitIndex + 1;
                                    end
                                else
                                    begin
                                        bitIndex <= 0;
                                        parityBit <= ^{data[6:0], rxDataStream}; 
                                        state <= PARITY_BIT;
                                    end
                            end
                    end
                PARITY_BIT:
                    begin
                        if (count < CYCLES_PER_BIT - 1)
                            begin    
                                count <= count + 1;
                            end
                        else
                            begin
                                count <= 0;

                                //Check parity
                                if (rxDataStream != parityBit)
                                    begin
                                        parityError <= 1;
                                    end
                                else
                                    begin
                                        parityError <= 0;
                                    end
                                    
                                state <= END_BIT;
                            end
                    end
                END_BIT:
                    begin
                        if (count < CYCLES_PER_BIT - 1)
                            begin
                                count <= count + 1;
                            end
                        else
                            begin
                                count <= 0;

                                if (!parityError)
                                    begin
                                        dataValid <= 1;
                                    end
                                else
                                    begin
                                        dataValid <= 0;
                                    end

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