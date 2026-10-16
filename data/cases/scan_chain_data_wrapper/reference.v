module scan_chain_data_wrapper (
    input wire clk_in,
    input wire data_in,
    input wire scan_select_in,
    input wire latch_enable_in,
    output wire clk_out,
    output wire data_out,
    output wire scan_select_out,
    output wire latch_enable_out
    );

    wire clk;
    assign clk = clk_in;  // Equivalent to the clock buffer

    wire data_out_i;
    assign clk_out = clk;
    assign scan_select_out = scan_select_in;
    assign latch_enable_out = latch_enable_in;

    parameter NUM_IOS = 8;

    wire [NUM_IOS-1:0] scan_data_out;   
    wire [NUM_IOS-1:0] scan_data_in;    
    wire [NUM_IOS-1:0] module_data_in;  
    wire [NUM_IOS-1:0] module_data_out; 

    assign scan_data_in = {scan_data_out[NUM_IOS-2:0], data_in};

    reg data_out_i_reg;
    always @(negedge clk) begin
        data_out_i_reg <= scan_data_out[NUM_IOS-1];
    end
    assign data_out_i = data_out_i_reg;

    reg [NUM_IOS-1:0] scan_data_out_reg;
    always @(posedge clk) begin
        if (scan_select_in)
            scan_data_out_reg <= module_data_out;
        else
            scan_data_out_reg <= scan_data_in;
    end
    assign scan_data_out = scan_data_out_reg;

    reg [NUM_IOS-1:0] module_data_in_reg;
    always @(posedge latch_enable_in) begin
        module_data_in_reg <= scan_data_out;
    end
    assign module_data_in = module_data_in_reg;

    // The contents of user_module_341457494561784402 would go here
    // For example:
    // assign module_data_out = some_logic(module_data_in);

    // Since the actual module is not provided, keeping as is.
    wire [NUM_IOS-1:0] module_io_in;
    wire [NUM_IOS-1:0] module_io_out;
    assign module_io_in = module_data_in;
    assign module_data_out = module_io_out;

    // The user module logic should be defined here
    // Example user module logic:
    // assign module_io_out = some_custom_logic(module_io_in);

endmodule