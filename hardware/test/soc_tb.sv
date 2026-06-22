`default_nettype none
`timescale 1ns / 1ps

`define SIMULATION

module execution_tb();
    parameter INIT="firmware.mem";
    parameter BAUD_RATE = 115200;
    parameter PTY_PATH = "/tmp/vserial";
    parameter WIDTH = 32;
    parameter DEPTH = 65536;
    parameter CYCLES_PER_BIT = 217;

    logic clock;

    initial clock = 0;

    localparam real CLOCK_HALF_PERIOD = 20;  // 25.0 MHz

    always #(CLOCK_HALF_PERIOD) clock = ~clock;

    logic reset;

    // UART signals
    logic uart_rx;
    logic uart_tx;
    // logic uart_cts = 1'b0; 
    // logic uart_rts;


    soc #(
        .INIT(INIT),
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .CYCLES_PER_BIT(CYCLES_PER_BIT)
    ) soc_inst (
        .clock,
        .reset,
        .rxDataStream(uart_rx),
        .txDataStream(uart_tx)
    );

    // PTY file descriptors
    integer sp_fd;  // For writing (Simulation -> picocom)
    integer ps_fd;  // For reading (picocom -> Simulation)

    // UART bit timing
    localparam BIT_PERIOD = 1_000_000_000 / BAUD_RATE;  // in ns

    // Task to receive a byte from the UART TX line
    task automatic recv_uart_tx(output logic [7:0] data);
        integer i;
        begin
            // Ensure we're in idle state before waiting for start bit
            // This prevents catching transitions within a byte
            wait (uart_tx == 1'b1);

            // Wait for start bit (falling edge)
            @(negedge uart_tx);

            // Wait for middle of first data bit
            #(BIT_PERIOD + BIT_PERIOD / 2);

            // Sample data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                data[i] = uart_tx;
                #(BIT_PERIOD);
            end

            // Wait for parity (ignored)
            #(BIT_PERIOD);

            // Now we're at the middle of the stop bit, check it
            if (uart_tx !== 1'b1) begin
                $display("UART framing error (stop bit low)");
                $finish;
            end
        end
    endtask

    // Task to send a byte to the UART RX line
    task automatic send_uart_rx(input logic [7:0] data);
        integer i;
        logic parity;
        begin
            // Calculate even parity
            parity = ^data;  // XOR all bits
            
            // Start bit
            uart_rx = 1'b0;
            #(BIT_PERIOD);

            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #(BIT_PERIOD);
            end
            
            // Parity bit (even parity)
            uart_rx = parity;
            #(BIT_PERIOD);

            // Stop bit
            uart_rx = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    // Process to continuously receive from UART TX and write to the file read by picocom
    initial begin
        logic [7:0] byte_recv;
        string sp_path;

        sp_path = {PTY_PATH, "_sp"};

        // Wait a bit for setup
        #2000;

        // Open TX file (write mode)
        sp_fd = $fopen(sp_path, "w");
        if (sp_fd == 0) begin
            $display("ERROR: Failed to open %s for writing", sp_path);
        end else begin
            $display("Opened %s for TX (sim -> picocom)", sp_path);
        end

        forever begin
            recv_uart_tx(byte_recv);
            $display("UART TX out (Sim->Picocom): 0x%02x (%c)", byte_recv, byte_recv);

            // Write to file
            if (sp_fd != 0) begin
                $fwrite(sp_fd, "%c", byte_recv);
                $fflush(sp_fd);
            end
        end
    end

    // Process to continuously read from file written by picocom and send to UART RX
    initial begin
        logic [7:0] byte_send;
        string ps_path;
        integer ps_position;

        integer read_result;

        uart_rx = 1'b1;  // Idle high

        ps_path = {PTY_PATH, "_ps"};

        // Wait a bit for setup
        #2000;

        ps_position = 0;

        // Continuously poll for data
        forever begin
            #(BIT_PERIOD * 10);  // Poll at reasonable intervals

            ps_fd = $fopen(ps_path, "r");

            if (ps_fd != 0) begin
                // Seek to where we left off
                if (ps_position > 0) begin
                    $fseek(ps_fd, ps_position, 0);
                end

                // Read all available bytes
                read_result = $fgetc(ps_fd);

                while (read_result >= 0 && read_result <= 255) begin
                    ps_position = ps_position + 1;
                    $display("UART RX in (Picocom->Simulation): 0x%02x (%c)", read_result, read_result);

                    byte_send = read_result[7:0];
                    send_uart_rx(byte_send);

                    read_result = $fgetc(ps_fd);
                end

                $fclose(ps_fd);
            end
        end
    end

    initial begin
        // Comment out VCD dump for faster testing
        // $dumpfile("execution2_tb.vcd");
        // $dumpvars(0, soc_inst);

        $display("Baud rate: %0d", BAUD_RATE);

        // Give SOC a moment to load MEM_INIT and start registers
        repeat (100) @(posedge clock);

        // Apply reset (stick for two rounds so it is detected at a posedge for synchronous resets)
        reset = 1;
        @(posedge clock);
        @(posedge clock);
        reset = 0;

        $display("SOC reset complete, starting execution...");
        $display("Press Ctrl+C to stop the simulation");

        // Comment to run forever - user will Ctrl+C to stop

        $dumpfile("soc_exec_tb.vcd");
        $dumpvars(0, soc_inst);

        #500_000_000; // Run for 100 ms max
        $finish;
    end
endmodule