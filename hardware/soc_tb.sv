module soc_tb();
    logic clock;
    logic reset = 1'b0;
    logic [3:0] leds;
    logic RXD;
    logic TXD;

    soc uut(
        .clock,
        .reset,
        .leds,
        .RXD,
        .TXD
    );

    logic [3:0] prev_leds = 0;

    initial
        begin

            clock = 0;

            forever
                begin
                    #1 clock = ~clock;

                    if (leds != prev_leds)
                        begin
                            $display("leds = %b", leds);
                        end

                    prev_leds <= leds;
                end
        end
endmodule