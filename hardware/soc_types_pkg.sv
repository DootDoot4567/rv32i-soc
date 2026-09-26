package soc_types_pkg;
    typedef enum int {
        INVALID = -1,
        BRAM,
        UART,
        CLINT
    } slave_id_t;

    typedef enum int {
        PROCESSOR
    } master_id_t;

    parameter DEPTH = 65536;
    parameter WIDTH = 32;

    parameter ADDR_WIDTH = 16;
    
    //Reset Address
    parameter [ADDR_WIDTH - 1:0] RESET_ADDRESS = 16'h8000;

    parameter int NUM_SLAVES = 3;
    parameter int NUM_MASTERS = 1;

    parameter [ADDR_WIDTH - 1:0] UART_BASE = 16'h0344;
    parameter [ADDR_WIDTH - 1:0] CLINT_BASE = 16'h0340;
    parameter [ADDR_WIDTH - 1:0] BRAM_BASE = 16'h0400;

    parameter [ADDR_WIDTH - 1:0] ADDR_MASK = 16'hFFFC;

endpackage
