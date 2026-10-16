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
reg [15:0] snapshot_l_register;
reg [15:0] snapshot_h_register;
reg timeout_occurred;
reg running;

// Control register bit definitions
wire control_interrupt_enable = control_register[0];
wire control_continuous = control_register[1];
wire start_strobe = control_register[2];
wire stop_strobe = control_register[3];

// Write strobes
wire write_strobe = chipselect && !write_n;
wire period_l_write = write_strobe && (address == 3'b000);
wire period_h_write = write_strobe && (address == 3'b001);
wire control_write = write_strobe && (address == 3'b010);

// Timeout detection
wire timeout = (internal_counter == 32'h0000_0000);
reg timeout_latched;

// Counter reload logic
wire reload_counter = period_l_write || period_h_write || (timeout && control_continuous && running);

// Snapshot logic
wire take_snapshot = write_strobe && (address == 3'b011);

// Asynchronous reset
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        // Reset values
        internal_counter <= 32'h0000_C34F;  // 49999 in decimal
        period_l_register <= 16'd49999;
        period_h_register <= 16'd0;
        control_register <= 16'h0000;
        snapshot_l_register <= 16'h0000;
        snapshot_h_register <= 16'h0000;
        timeout_occurred <= 1'b0;
        running <= 1'b0;
        timeout_latched <= 1'b0;
        irq <= 1'b0;
    end
    else begin
        // Handle control register writes
        if (control_write) begin
            control_register <= writedata;
            
            // Start/stop logic
            if (writedata[2]) begin  // start_strobe
                running <= 1'b1;
            end
            if (writedata[3]) begin  // stop_strobe
                running <= 1'b0;
            end
        end
        
        // Handle period register writes
        if (period_l_write) begin
            period_l_register <= writedata;
        end
        if (period_h_write) begin
            period_h_register <= writedata;
        end
        
        // Handle snapshot
        if (take_snapshot) begin
            snapshot_l_register <= internal_counter[15:0];
            snapshot_h_register <= internal_counter[31:16];
        end
        
        // Counter reload logic
        if (reload_counter) begin
            internal_counter <= {period_h_register, period_l_register};
        end
        // Counter decrement logic
        else if (running && !timeout) begin
            internal_counter <= internal_counter - 32'h0000_0001;
        end
        
        // Timeout latch for debouncing
        timeout_latched <= timeout;
        
        // Timeout occurred register (edge detection)
        if (timeout && !timeout_latched && running) begin
            timeout_occurred <= 1'b1;
        end
        else if (write_strobe && (address == 3'b100)) begin
            // Clear timeout_occurred when writing to timeout status register
            timeout_occurred <= 1'b0;
        end
        
        // IRQ generation
        irq <= timeout_occurred && control_interrupt_enable;
    end
end

// Read data multiplexer
always @(*) begin
    case (address)
        3'b000: readdata = period_l_register;
        3'b001: readdata = period_h_register;
        3'b010: readdata = control_register;
        3'b011: readdata = snapshot_l_register;
        3'b100: readdata = {15'h0000, timeout_occurred};
        3'b101: readdata = snapshot_h_register;
        3'b110: readdata = internal_counter[15:0];
        3'b111: readdata = internal_counter[31:16];
        default: readdata = 16'h0000;
    endcase
end

endmodule
