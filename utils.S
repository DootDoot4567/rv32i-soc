.global read_cycles
.global read_instr_retired

read_cycles:
1:
    rdcycle a1
    rdcycle a0
    rdcycle t0
    bne a1, t0, 1b
    ret

read_instr_retired:
1:
    rdinstrh a1
    rdinstrh a0
    rdinstrh t0
    bne a1, t0, 1b
    ret