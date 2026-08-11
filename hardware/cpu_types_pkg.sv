package cpu_types_pkg;
    typedef enum logic [1:0] {
        USER = 2'b00,
        SUPERVISOR = 2'b01,
        //RESERVED - Hypervisor?
        MACHINE = 2'b11
    } mode_t;
endpackage

