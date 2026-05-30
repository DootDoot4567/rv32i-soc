module reg_forwarder (
    input logic [4:0] d_rs1Id,
    input logic [4:0] d_rs2Id,

    input logic [4:0] e_rs1Id,
    input logic [4:0] e_rs2Id,

    input logic [31:0] de_rs1,
    input logic [31:0] de_rs2,

    input logic [4:0] em_rdId,
    input logic [4:0] mw_rdId,

    input logic m_writesRd,
    input logic w_writesRd,

    input logic [31:0] em_writeBackData,
    input logic [31:0] mw_writeBackData,
    
    input logic mw_isLoad,
    input logic [31:0] w_loadData,
    input logic [31:0] registerFile [0:31],

    output logic [31:0] d_rs1Forwarded,
    output logic [31:0] d_rs2Forwarded,
    output logic [31:0] e_rs1Forwarded,
    output logic [31:0] e_rs2Forwarded,

    output logic em_fwd_rs1,
    output logic ew_fwd_rs1,
    output logic em_fwd_rs2,
    output logic ew_fwd_rs2
);
    logic [31:0] wb_writeData;
    
    assign wb_writeData = mw_isLoad ? w_loadData : mw_writeBackData;

    assign em_fwd_rs1 = (em_rdId != 0) && m_writesRd && (em_rdId == e_rs1Id);
    assign em_fwd_rs2 = (em_rdId != 0) && m_writesRd && (em_rdId == e_rs2Id);

    assign ew_fwd_rs1 = (mw_rdId != 0) && w_writesRd && (mw_rdId == e_rs1Id);
    assign ew_fwd_rs2 = (mw_rdId != 0) && w_writesRd && (mw_rdId == e_rs2Id);

    always_comb 
        begin
            if (em_fwd_rs1) 
                begin
                    e_rs1Forwarded = em_writeBackData;
                end
            else if (ew_fwd_rs1) 
                begin
                    e_rs1Forwarded = wb_writeData;
                end
            else 
                begin
                    e_rs1Forwarded = de_rs1;
                end
        end

    always_comb 
        begin
            if (em_fwd_rs2) 
                begin
                    e_rs2Forwarded = em_writeBackData;
                end
            else if (ew_fwd_rs2) 
                begin
                    e_rs2Forwarded = wb_writeData;
                end
            else 
                begin
                    e_rs2Forwarded = de_rs2;
                end
        end

     always_comb 
        begin
            if (m_writesRd && em_rdId != 0 && em_rdId == d_rs1Id)
                begin
                    d_rs1Forwarded = em_writeBackData;
                end
            else if (w_writesRd && mw_rdId != 0 && mw_rdId == d_rs1Id)
                begin
                    d_rs1Forwarded = mw_isLoad ? w_loadData : mw_writeBackData;
                end
            else
                begin
                    d_rs1Forwarded = registerFile[d_rs1Id];
                end
        end

    always_comb 
        begin
            if (m_writesRd && em_rdId != 0 && em_rdId == d_rs2Id)
                begin
                    d_rs2Forwarded = em_writeBackData;
                end
            else if (w_writesRd && mw_rdId != 0 && mw_rdId == d_rs2Id)
                begin
                    d_rs2Forwarded = mw_isLoad ? w_loadData : mw_writeBackData;
                end
            else
                begin
                    d_rs2Forwarded = registerFile[d_rs2Id];
                end
        end


endmodule