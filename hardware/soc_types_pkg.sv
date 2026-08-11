package soc_types_pkg;
    typedef enum int {
        BRAM,
        UART,
        CLINT
    } slave_id_t;

    typedef enum int {
        PROCESSOR
    } master_id_t;

    parameter DEPTH = 65536;
    parameter WIDTH = 32;

    //Computes minimum bits needed for the mem addresses using log_2(depth)
    parameter ADDR_WIDTH = $clog2(DEPTH);
    
    //Reset Address
    parameter [ADDR_WIDTH - 1:0] RESET_ADDRESS = 32'h00008000;

    parameter int NUM_SLAVES = 3;
    parameter int NUM_MASTERS = 1;

    //UART BASE: 0x0340;
    //CLINT BASE: 0x0344;
    logic [NUM_SLAVES - 2:0][ADDR_WIDTH - 1:0] IO_BASE = {16'h0344, 16'h0340};

    //UART MASK: 0xFFFC;
    //CLINT MASK: 0xFFFC;
    logic [NUM_SLAVES - 2:0][ADDR_WIDTH - 1:0] ADDR_MASK = {16'hFFFC, 16'hFFFC};

endpackage
