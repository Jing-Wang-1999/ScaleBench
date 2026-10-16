module programmable_alarm_timer_50m (
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
    reg [15:0] snapshot_l_register;
    reg [15:0] snapshot_h_register;
    reg [15:0] control_register;
    reg timeout_latch;

    // Control signals
    wire start_strobe;
    wire stop_strobe;
    wire period_l_wr_strobe;
    wire period_h_wr_strobe;
    wire control_wr_strobe;
    wire snapshot_strobe;

    // Assign control signals based on address and chipselect
    assign period_l_wr_strobe = chipselect && (address == 3'b000) && ~write_n;
    assign period_h_wr_strobe = chipselect && (address == 3'b001) && ~write_n;
    assign control_wr_strobe  = chipselect && (address == 3'b010) && ~write_n;
    assign snapshot_strobe    = chipselect && (address == 3'b011) && write_n;
    assign start_strobe       = control_wr_strobe && writedata[0];
    assign stop_strobe        = control_wr_strobe && writedata[1];

    // Asynchronous reset
    always @(negedge reset_n or posedge clk) begin
        if (!reset_n) begin
            internal_counter <= 32'h02FA_F07F;
            period_l_register <= 16'd61567;
            period_h_register <= 16'd762;
            control_register <= 16'b0;
            timeout_latch <= 1'b0;
            irq <= 1'b0;
        end else begin
            // Write operations
            if (period_l_wr_strobe) begin
                period_l_register <= writedata;
            end
            if (period_h_wr_strobe) begin
                period_h_register <= writedata;
            end
            if (control_wr_strobe) begin
                control_register <= writedata;
                if (writedata[2]) begin
                    timeout_latch <= 1'b0; // Clear timeout latch
                end
            end

            // Counter operation
            if (start_strobe) begin
                internal_counter <= {period_h_register, period_l_register};
            end else if (stop_strobe) begin
                // Do nothing, counter is stopped
            end else if (internal_counter != 0) begin
                internal_counter <= internal_counter - 1;
            end else if (internal_counter == 0 && control_register[3]) begin
                internal_counter <= {period_h_register, period_l_register}; // Reload in continuous mode
            end

            // Timeout and IRQ handling
            if (internal_counter == 0 && !timeout_latch) begin
                timeout_latch <= 1'b1;
                if (control_register[4]) begin
                    irq <= 1'b1; // Set IRQ if enabled
                end
            end

            // Snapshot operation
            if (snapshot_strobe) begin
                snapshot_l_register <= internal_counter[15:0];
                snapshot_h_register <= internal_counter[31:16];
            end
        end
    end

    // Read operations
    always @(*) begin
        case (address)
            3'b000: readdata = period_l_register;
            3'b001: readdata = period_h_register;
            3'b010: readdata = control_register;
            3'b011: readdata = snapshot_l_register;
            3'b100: readdata = snapshot_h_register;
            default: readdata = 16'b0;
        endcase
    end

endmodule
