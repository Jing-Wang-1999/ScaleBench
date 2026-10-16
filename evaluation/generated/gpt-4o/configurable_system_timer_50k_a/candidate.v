module configurable_system_timer_50k_a (
    input [2:0] address,
    input chipselect,
    input clk,
    input reset_n,
    input write_n,
    input [15:0] writedata,
    output reg irq,
    output reg [15:0] readdata
);

    // Internal registers
    reg [31:0] internal_counter;
    reg [15:0] period_l_register;
    reg [15:0] period_h_register;
    reg [15:0] control_register;
    reg timeout_occurred;

    // Control register bits
    wire control_interrupt_enable = control_register[0];
    wire control_continuous = control_register[1];
    wire start_strobe = control_register[2];
    wire stop_strobe = control_register[3];

    // Address decoding
    localparam ADDR_COUNTER = 3'b000;
    localparam ADDR_CONTROL = 3'b001;
    localparam ADDR_PERIOD_L = 3'b010;
    localparam ADDR_PERIOD_H = 3'b011;

    // Asynchronous reset
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            internal_counter <= 32'h0000_C34F;
            period_l_register <= 16'd49999;
            period_h_register <= 16'd0;
            control_register <= 16'd0;
            timeout_occurred <= 1'b0;
            irq <= 1'b0;
        end else begin
            // Write operations
            if (chipselect && !write_n) begin
                case (address)
                    ADDR_CONTROL: control_register <= writedata;
                    ADDR_PERIOD_L: period_l_register <= writedata;
                    ADDR_PERIOD_H: period_h_register <= writedata;
                endcase
            end

            // Timer operation
            if (start_strobe) begin
                internal_counter <= {period_h_register, period_l_register};
                timeout_occurred <= 1'b0;
            end else if (stop_strobe) begin
                internal_counter <= internal_counter; // Hold the counter
            end else if (internal_counter != 0) begin
                internal_counter <= internal_counter - 1;
            end else if (internal_counter == 0) begin
                if (control_continuous) begin
                    internal_counter <= {period_h_register, period_l_register};
                end
                timeout_occurred <= 1'b1;
            end

            // Interrupt generation
            if (timeout_occurred && control_interrupt_enable) begin
                irq <= 1'b1;
            end else begin
                irq <= 1'b0;
            end
        end
    end

    // Read operations
    always @(*) begin
        case (address)
            ADDR_COUNTER: readdata = internal_counter[15:0];
            ADDR_CONTROL: readdata = control_register;
            ADDR_PERIOD_L: readdata = period_l_register;
            ADDR_PERIOD_H: readdata = period_h_register;
            default: readdata = 16'h0000;
        endcase
    end

endmodule
