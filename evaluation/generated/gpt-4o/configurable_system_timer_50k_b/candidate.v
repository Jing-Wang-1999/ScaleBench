module configurable_system_timer_50k_b (
    input [2:0] address,
    input chipselect,
    input clk,
    input reset_n,
    input write_n,
    input [31:0] writedata,
    output reg irq,
    output reg [31:0] readdata
);

    // Internal registers
    reg [31:0] internal_counter;
    reg [15:0] period_l_register;
    reg [15:0] period_h_register;
    reg control_continuous;
    reg control_interrupt_enable;
    reg delayed_unxcounter_is_zeroxx0;
    reg [31:0] snapshot_counter;

    // Control signals
    wire start_strobe;
    wire stop_strobe;
    wire force_reload;
    wire snap_l_wr_strobe;
    wire snap_h_wr_strobe;

    // Address decoding
    assign start_strobe = chipselect && ~write_n && (address == 3'b000);
    assign stop_strobe = chipselect && ~write_n && (address == 3'b001);
    assign force_reload = chipselect && ~write_n && (address == 3'b010);
    assign snap_l_wr_strobe = chipselect && ~write_n && (address == 3'b011);
    assign snap_h_wr_strobe = chipselect && ~write_n && (address == 3'b100);

    // Asynchronous reset
    always @(negedge reset_n or posedge clk) begin
        if (!reset_n) begin
            internal_counter <= 32'h0000_C34F;
            period_l_register <= 16'd49999;
            period_h_register <= 16'd0;
            control_continuous <= 1'b0;
            control_interrupt_enable <= 1'b0;
            delayed_unxcounter_is_zeroxx0 <= 1'b0;
            irq <= 1'b0;
        end else begin
            // Counter operation
            if (start_strobe) begin
                internal_counter <= {period_h_register, period_l_register};
            end else if (stop_strobe) begin
                internal_counter <= internal_counter;
            end else if (internal_counter == 32'd0 || force_reload) begin
                internal_counter <= {period_h_register, period_l_register};
            end else if (internal_counter != 32'd0) begin
                internal_counter <= internal_counter - 1;
            end

            // Timeout and interrupt handling
            if (internal_counter == 32'd0 && delayed_unxcounter_is_zeroxx0 && control_interrupt_enable) begin
                irq <= 1'b1;
            end else if (chipselect && ~write_n && (address == 3'b101)) begin
                irq <= 1'b0; // Clear interrupt
            end

            // Snapshot handling
            if (snap_l_wr_strobe || snap_h_wr_strobe) begin
                snapshot_counter <= internal_counter;
            end

            // Delayed zero detection
            delayed_unxcounter_is_zeroxx0 <= (internal_counter == 32'd0);

            // Register writes
            if (chipselect && ~write_n) begin
                case (address)
                    3'b110: begin
                        period_l_register <= writedata[15:0];
                        period_h_register <= writedata[31:16];
                    end
                    3'b111: begin
                        control_continuous <= writedata[0];
                        control_interrupt_enable <= writedata[1];
                    end
                endcase
            end
        end
    end

    // Read data multiplexing
    always @(*) begin
        case (address)
            3'b000: readdata = {31'b0, irq};
            3'b001: readdata = {31'b0, delayed_unxcounter_is_zeroxx0};
            3'b010: readdata = {period_h_register, period_l_register};
            3'b011: readdata = {30'b0, control_interrupt_enable, control_continuous};
            3'b100: readdata = snapshot_counter;
            default: readdata = 32'b0;
        endcase
    end

endmodule
