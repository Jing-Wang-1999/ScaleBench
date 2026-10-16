module i2c_command_sender(
    input clk,
    inout siod,
    output reg sioc,
    output reg taken,
    input send,
    input [7:0] id,
    input [7:0] rega,
    input [7:0] value
);
                        
    reg [7:0] divider = 8'b00000001;
    reg [31:0] busy_sr = {32{1'b0}};
    reg [31:0] data_sr = {32{1'b1}};
    reg siod_temp;
    
    assign siod = (siod_temp) ? 1'bZ : 1'b0;
    
    always @(*)
    begin
        if (busy_sr[11:10] == 2'b10 || busy_sr[20:19] == 2'b10 || busy_sr[29:28] == 2'b10)
            siod_temp <= 1'bZ;
        else
            siod_temp <= data_sr[31];
    end

    always @(posedge clk)
    begin
        taken <= 1'b0;
        if (busy_sr[31] == 0)
        begin
            sioc <= 1;
            if (send == 1)
            begin
                if (divider == 8'b00000001)
                begin
                    data_sr <= {3'b100, id, 1'b0, rega, 1'b0, value, 1'b0, 2'b01};
                    busy_sr <= {3'b111, 9'b111111111, 9'b111111111, 9'b111111111, 2'b11};
                    taken <= 1'b1;
                end
                else
                begin
                    divider <= divider + 1;
                end
            end
        end
        else
        begin
            if (busy_sr[31:29] == 3'b111 && busy_sr[2:0] == 3'b111)
                sioc <= 1;
            else if(busy_sr[31:29] == 3'b111 && busy_sr[2:0] == 3'b110)
                sioc <= 1;
            else if (busy_sr[31:29] == 3'b111 && busy_sr[2:0] == 3'b100)
                sioc <= 0;
            else if (busy_sr[31:29] == 3'b111 && busy_sr[2:0] == 3'b111 && (divider[7:6] == 2'b01 || divider[7:6] == 2'b10 || divider[7:6] == 2'b11))
                sioc <= 1;
            else if (busy_sr[31:29] == 3'b111 && busy_sr[2:0] == 3'b111 && divider[7:6] == 2'b00)
                sioc <= 0;
            else if (busy_sr[31:29] == 3'b100 && busy_sr[2:0] == 3'b000)
                sioc <= 1;
            else if (busy_sr[31:29] == 3'b000 && busy_sr[2:0] == 3'b000)
                sioc <= 1;
            else
            begin
                if (divider[7:6] == 2'b00 || divider[7:6] == 2'b11)
                    sioc <= 0;
                else if (divider[7:6] == 2'b01 || divider[7:6] == 2'b10)
                    sioc <= 1;
            end
            
            if (divider == 8'b11111111)
            begin
                busy_sr <= {busy_sr[30:0], 1'b0};
                data_sr <= {data_sr[30:0], 1'b1};
                divider <= {8{1'b0}};
            end
            else
            begin
                divider <= divider + 1;
            end
        end
    end
endmodule