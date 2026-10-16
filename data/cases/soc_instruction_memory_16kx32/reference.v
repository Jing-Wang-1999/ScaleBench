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

  parameter INIT_FILE = "../SoC_ins_mem0.hex";

  output reg [31:0] readdata;
  input [13:0] address;
  input [3:0] byteenable;
  input chipselect;
  input clk;
  input clken;
  input reset;
  input write;
  input [31:0] writedata;

  wire wren;
  assign wren = chipselect & write;

  reg [31:0] memory [0:16383];  // Defining the memory for a total of 16384 addresses

  // Initialize memory from a file during synthesis
  initial begin
    $readmemh(INIT_FILE, memory);
  end

  always @(posedge clk) begin
    if (clken) begin
      if (wren) begin
        // Byte-enable write logic
        if (byteenable[0]) memory[address][7:0] <= writedata[7:0];
        if (byteenable[1]) memory[address][15:8] <= writedata[15:8];
        if (byteenable[2]) memory[address][23:16] <= writedata[23:16];
        if (byteenable[3]) memory[address][31:24] <= writedata[31:24];
      end
      readdata <= memory[address];  // Read logic
    end
  end

endmodule