module clock_divider_output_taps(clock, reset, imem_clock, dmem_clock, processor_clock, regfile_clock);
    input clock, reset;
    
    output imem_clock, dmem_clock, processor_clock, regfile_clock;
    wire [7:0] clks;
    
    // clocks module functionality
    reg [7:0] clk_div;
    
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            clk_div <= 8'd0;
        end else begin
            clk_div <= clk_div + 1;
        end
    end
    
    assign clks = clk_div;

    assign imem_clock = clks[0];
    assign dmem_clock = clks[5];
    assign regfile_clock = clks[5];
    assign processor_clock = clks[7];

    // imem module functionality
    reg [31:0] mem_imem [0:4095]; // 4096 words memory
    reg [31:0] q_imem_reg;
    wire [11:0] address_imem;
    wire [31:0] q_imem;
    
    always @(posedge imem_clock) begin
        q_imem_reg <= mem_imem[address_imem];
    end
    
    assign q_imem = q_imem_reg;

    // dmem module functionality
    reg [31:0] mem_dmem [0:4095]; // 4096 words memory
    reg [31:0] q_dmem_reg;
    wire [11:0] address_dmem;
    wire [31:0] data;
    wire wren;
    wire [31:0] q_dmem;

    always @(posedge dmem_clock) begin
        if (wren) begin
            mem_dmem[address_dmem] <= data;
        end
        q_dmem_reg <= mem_dmem[address_dmem];
    end

    assign q_dmem = q_dmem_reg;

    // regfile module functionality
    reg [31:0] regfile [0:31];
    
    wire ctrl_writeEnable;
    wire [4:0] ctrl_writeReg, ctrl_readRegA, ctrl_readRegB;
    wire [31:0] data_writeReg;
    wire [31:0] data_readRegA, data_readRegB;

    always @(posedge regfile_clock or posedge reset) begin
        if (reset) begin
            integer i;
            for (i = 0; i < 32; i = i + 1) begin
                regfile[i] <= 32'd0;
            end
        end else if (ctrl_writeEnable) begin
            regfile[ctrl_writeReg] <= data_writeReg;
        end
    end

    assign data_readRegA = regfile[ctrl_readRegA];
    assign data_readRegB = regfile[ctrl_readRegB];

    // Simplified processor module functionality
    reg [11:0] address_imem_reg;
    reg [11:0] address_dmem_reg;
    reg [31:0] data_reg;
    reg wren_reg;
    reg ctrl_writeEnable_reg;
    reg [4:0] ctrl_writeReg_reg, ctrl_readRegA_reg, ctrl_readRegB_reg;
    reg [31:0] data_writeReg_reg;
    
    always @(posedge processor_clock or posedge reset) begin
        if (reset) begin
            address_imem_reg <= 12'd0;
            address_dmem_reg <= 12'd0;
            data_reg <= 32'd0;
            wren_reg <= 1'b0;
            ctrl_writeEnable_reg <= 1'b0;
            ctrl_writeReg_reg <= 5'd0;
            ctrl_readRegA_reg <= 5'd0;
            ctrl_readRegB_reg <= 5'd0;
            data_writeReg_reg <= 32'd0;
        end else begin
            // Processor logic can be further implemented here.
            // Currently assigning defaults.
            address_imem_reg <= 12'd1;
            address_dmem_reg <= 12'd2;
            data_reg <= 32'd3;
            wren_reg <= 1'b0;
            ctrl_writeEnable_reg <= 1'b0;
            ctrl_writeReg_reg <= 5'd1;
            ctrl_readRegA_reg <= 5'd2;
            ctrl_readRegB_reg <= 5'd3;
            data_writeReg_reg <= 32'd4;
        end
    end

    assign address_imem = address_imem_reg;
    assign address_dmem = address_dmem_reg;
    assign data = data_reg;
    assign wren = wren_reg;
    assign ctrl_writeEnable = ctrl_writeEnable_reg;
    assign ctrl_writeReg = ctrl_writeReg_reg;
    assign ctrl_readRegA = ctrl_readRegA_reg;
    assign ctrl_readRegB = ctrl_readRegB_reg;
    assign data_writeReg = data_writeReg_reg;
endmodule
