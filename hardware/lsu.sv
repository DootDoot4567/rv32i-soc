module lsu #(
    parameter WIDTH = 32
) (

    input logic [31:0] loadAddr,
    input logic [31:0] storeAddr,
    input logic [31:0] rs2,
    input logic [WIDTH - 1:0] dataRead,
    input logic [2:0] funct3,

    output logic [31:0] storeData,
    output logic [31:0] loadData,
    output logic [3:0] storeMask
);
    //Helper variables to help compute loadData
    logic [15:0] loadHalf;
    logic [7:0] loadByte;
    
    //Load logic for half and full words and bytes
    always @(*)
        begin
            loadHalf = loadAddr[1] ? dataRead[31:16] : dataRead[15:0];

            case(loadAddr[1:0])
                0: loadByte = dataRead[7:0];
                1: loadByte = dataRead[15:8];
                2: loadByte = dataRead[23:16];
                3: loadByte = dataRead[31:24];

                default: loadByte = 8'b0;
            endcase

            case(funct3)
                3'b000: loadData = {{24{loadByte[7]}}, loadByte};
                3'b001: loadData = {{16{loadHalf[15]}}, loadHalf};
                3'b100: loadData = {24'b0, loadByte};
                3'b101: loadData = {16'b0, loadHalf};

                default: loadData = dataRead;
            endcase
        end

    //Store logic, combinatorially builds the word stored
    always @(*)
        begin
            storeData = 32'b0;
            storeMask = 4'b0000;

            case (funct3)
                3'b000:
                    begin
                        storeData = {rs2[7:0], rs2[7:0], rs2[7:0], rs2[7:0]};
                        storeMask = 4'b0001 << storeAddr[1:0];
                    end

                3'b001: 
                    begin
                        storeData = {rs2[15:0], rs2[15:0], rs2[15:0], rs2[15:0]};
                        storeMask = 4'b0011 << {storeAddr[1], 1'b0};
                    end

                3'b010: 
                    begin
                        storeData = rs2;
                        storeMask = 4'b1111;
                    end

                default: 
                    begin
                        storeData = 32'b0;
                        storeMask = 4'b0000;
                    end
            endcase
        end

endmodule