.global read_cycles
.global read_instr_retired

read_cycles:
1:
    #Read upper immediate 32 bits on cycle counter
    rdcycleh a1
    #Read lower immediate 32 bits on cycle counter
    rdcycle a0
    rdcycleh t0
    bne a1, t0, 1b
    ret

read_instr_retired:
1:
    //Read upper immediate 32 bits from instructions returned
    rdinstreth a1
    //Read lower immediate 32 bits from instructions returned
    rdinstret a0
    rdinstreth t0
    bne a1, t0, 1b
    ret