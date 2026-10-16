module soc_instruction_memory_16kx32 (
    address,
    byteenable,
    chipselect,
    clk,
    clken,
    reset,
    write,
    writedata,
    readdata
);
    output reg [31:0] readdata;
    input [13:0] address;
    input [3:0] byteenable;
    input chipselect;
    input clk;
    input clken;
    input reset;
    input write;
    input [31:0] writedata;

    wire wren = chipselect & write;

    reg [31:0] memory [0:16383];
    reg [16383:0] valid;
    wire [31:0] addressed_word = valid[address]
        ? memory[address]
        : 32'b0;
    reg [31:0] write_word;

    always @(*) begin
        write_word = addressed_word;
        if (byteenable[0]) write_word[7:0] = writedata[7:0];
        if (byteenable[1]) write_word[15:8] = writedata[15:8];
        if (byteenable[2]) write_word[23:16] = writedata[23:16];
        if (byteenable[3]) write_word[31:24] = writedata[31:24];
    end

    always @(posedge clk) begin
        if (reset) begin
            valid <= {16384{1'b0}};
            readdata <= 32'b0;
        end else if (clken) begin
            if (wren) begin
                memory[address] <= write_word;
                valid[address] <= 1'b1;
            end
            readdata <= addressed_word;
        end
    end
endmodule
