module lsu #(
    parameter WIDTH = 32
) (

    input logic [31:0] memAddr,
    input logic [31:0] rs2,
    input logic [WIDTH - 1:0] dataOut,
    input logic [2:0] funct3,

    output logic [31:0] storeData,
    output logic [31:0] loadData 
);
    //Helper variables to help compute loadData
    logic [15:0] loadHalf;
    logic [7:0] loadByte;
    
    //Load logic for half and full words and bytes
    always @(*)
        begin
            loadHalf = memAddr[1] ? dataOut[31:16] : dataOut[15:0];

            case(memAddr[1:0])
                0: loadByte = dataOut[7:0];
                1: loadByte = dataOut[15:8];
                2: loadByte = dataOut[23:16];
                3: loadByte = dataOut[31:24];
            endcase

            case(funct3)
                3'b000: loadData = {{24{loadByte[7]}}, loadByte};
                3'b001: loadData = {{16{loadHalf[15]}}, loadHalf};
                3'b100: loadData = {24'b0, loadByte};
                3'b101: loadData = {16'b0, loadHalf};

                default:
                    loadData = dataOut;
            
            endcase
        end

    //Store logic, combinatorially builds the word stored
    always @(*)
        begin
            if (funct3 == 3'b000)
                begin
                    case(memAddr[1:0])
                        0: storeData[7:0]   = rs2[7:0];
                        1: storeData[15:8]  = rs2[7:0];
                        2: storeData[23:16] = rs2[7:0];
                        3: storeData[31:24] = rs2[7:0];
                    endcase
                end
            
            else if (funct3 == 3'b001)
                begin
                    case(memAddr[1:0])
                        0: storeData[15:0]   = rs2[15:0];
                        3: storeData[31:16] = rs2[15:0];
                    endcase
                end

            else if (funct3 == 3'b010)
                begin
                    storeData = rs2;
                end
        end


endmodule