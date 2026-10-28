import cpu_types_pkg::*;

module pmp #(
    parameter NUM_ENTRIES = 16
) (
    input logic [31:0] checkAddr,
    input logic isWrite,
    input logic isExec,
    input mode_t currentMode,

    input logic [63:0][31:0] pmpAddr,
    input logic [15:0][31:0] pmpCfg,

    output logic accessFault
);
    logic [NUM_ENTRIES - 1:0] matched;
    
    logic [NUM_ENTRIES - 1:0][31:0] loBound;
    logic [NUM_ENTRIES - 1:0][31:0] hiBound;

    always_comb
        begin
            for (int i = 0; i < NUM_ENTRIES; i = i + 1)
                begin
                    loBound[i] = (i == 0) ? 32'd0 : {pmpAddr[i-1], 2'b00};
                    hiBound[i] = {pmpAddr[i], 2'b00};
                end
        end

    //for a NAPOT-encoded address field,
    //XOR with itself+1 turns every trailing 1-bit (plus the terminating 0)
    // into a 1 in the mask
    function automatic logic napotMatch(input logic [31:0] addr, input logic [31:0] napotAddr);
        logic [31:0] mask;
        mask = napotAddr ^ (napotAddr + 32'd1);
        napotMatch = ((addr[31:2] & ~mask) == (napotAddr & ~mask));
    endfunction

    always_comb
        begin
            for (int j = 0; j < NUM_ENTRIES; j = j + 1)
                begin
                    logic [31:0] cfgEntry;
                    logic [31:0] addrEntry;

                    cfgEntry  = pmpCfg[j];
                    addrEntry = pmpAddr[j];

                    case (cfgEntry[4:3])
                        2'b00: matched[j] = 1'b0; // OFF
                        2'b01: matched[j] = (checkAddr >= loBound[j]) && (checkAddr < hiBound[j]); // TOR
                        2'b10: matched[j] = (checkAddr[31:2] == addrEntry[31:2]); // NA4
                        2'b11: matched[j] = napotMatch(checkAddr, addrEntry); // NAPOT
                        default: matched[j] = 1'b0;
                    endcase
                end
        end

    //First-match priority: entry 0 has highest priority, so we scan
    //high-to-low and let the low-index write win last
    //L bit (cfg[7]) makes the rule apply even in M-mode; without it,
    //M-mode bypasses PMP entirely for that entry

    always_comb
        begin
            accessFault = (currentMode != MACHINE); //default: deny U w/ no match, allow M
            for (int j = NUM_ENTRIES - 1; j >= 0; j = j - 1)
                begin
                    logic [31:0] cfgEntry;
                    cfgEntry = pmpCfg[j];

                    if (matched[j])
                        begin
                            if ((currentMode != MACHINE) || cfgEntry[7])
                                accessFault = isWrite ? !cfgEntry[1] :
                                            isExec  ? !cfgEntry[2] :
                                                        !cfgEntry[0];
                            else
                                accessFault = 1'b0;
                        end
                end
        end
endmodule
