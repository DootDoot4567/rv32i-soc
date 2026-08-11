module reg_forwarder (
    input logic [4:0] d_rs1Id,
    input logic [4:0] d_rs2Id,

    input logic [4:0] de_rs1Id,
    input logic [4:0] de_rs2Id,

    input logic [31:0] d_rs1Data,
    input logic [31:0] d_rs2Data,

    input logic [31:0] e_rs1Data,
    input logic [31:0] e_rs2Data,

    input logic [4:0] em_rdId,
    input logic [4:0] mw_rdId,

    input logic m_writesRd,
    input logic w_writesRd,

    input logic [31:0] em_writeBackData,
    input logic [31:0] mw_writeBackData,
    
    input logic mw_isLoad,
    input logic [31:0] w_loadData,

    output logic [31:0] d_rs1Forwarded,
    output logic [31:0] d_rs2Forwarded,
    output logic [31:0] e_rs1Forwarded,
    output logic [31:0] e_rs2Forwarded
);
    always_comb 
        begin
            if (m_writesRd && (em_rdId != 0) && (em_rdId == de_rs1Id)) 
                begin
                    e_rs1Forwarded = em_writeBackData;
                end
            else if (w_writesRd && (mw_rdId != 0) && (mw_rdId == de_rs1Id)) 
                begin
                    e_rs1Forwarded = mw_isLoad ? w_loadData : mw_writeBackData;
                end
            else 
                begin
                    e_rs1Forwarded = e_rs1Data;
                end
        end

    always_comb 
        begin
            if (m_writesRd && (em_rdId != 0) && (em_rdId == de_rs2Id)) 
                begin
                    e_rs2Forwarded = em_writeBackData;
                end
            else if (w_writesRd && (mw_rdId != 0) && (mw_rdId == de_rs2Id)) 
                begin
                    e_rs2Forwarded = mw_isLoad ? w_loadData : mw_writeBackData;
                end
            else 
                begin
                    e_rs2Forwarded = e_rs2Data;
                end
        end

     always_comb 
        begin
            if (m_writesRd && (em_rdId != 0) && (em_rdId == d_rs1Id))
                begin
                    d_rs1Forwarded = em_writeBackData;
                end
            else if (w_writesRd && (mw_rdId != 0) && (mw_rdId == d_rs1Id))
                begin
                    d_rs1Forwarded = mw_isLoad ? w_loadData : mw_writeBackData;
                end
            else
                begin
                    d_rs1Forwarded = d_rs1Data;
                end
        end

    always_comb 
        begin
            if (m_writesRd && (em_rdId != 0) && (em_rdId == d_rs2Id))
                begin
                    d_rs2Forwarded = em_writeBackData;
                end
            else if (w_writesRd && (mw_rdId != 0) && (mw_rdId == d_rs2Id))
                begin
                    d_rs2Forwarded = mw_isLoad ? w_loadData : mw_writeBackData;
                end
            else
                begin
                    d_rs2Forwarded = d_rs2Data;
                end
        end

endmodule
