module ddr2_sequencer_memory_4kx32 (
    address,
    byteenable,
    chipselect,
    clk,
    clken,
    debugaccess,
    reset,
    write,
    writedata,
    readdata
);
    parameter INIT_FILE = "altera_mem_if_ddr2_phy_0001_sequencer_rom.hex";
    
    output reg [31:0] readdata;
    input [11:0] address;
    input [3:0] byteenable;
    input chipselect;
    input clk;
    input clken;
    input debugaccess;
    input reset;
    input write;
    input [31:0] writedata;
    
    wire wren;
    assign wren = chipselect & write & debugaccess;

    reg [31:0] memory[0:4095];
    initial begin
        $readmemh(INIT_FILE, memory);
    end

    always @(posedge clk) begin
        if (clken) begin
            if (wren) begin
                // Handle byte enables
                if(byteenable[0]) memory[address][7:0]   <= writedata[7:0];
                if(byteenable[1]) memory[address][15:8]  <= writedata[15:8];
                if(byteenable[2]) memory[address][23:16] <= writedata[23:16];
                if(byteenable[3]) memory[address][31:24] <= writedata[31:24];
            end
            readdata <= memory[address];
        end
    end
endmodule