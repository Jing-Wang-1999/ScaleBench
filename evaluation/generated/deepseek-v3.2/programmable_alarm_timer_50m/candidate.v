module programmable_alarm_timer_50m (
    input [2:0] address,
    input chipselect,
    input clk,
    input reset_n,
    input write_n,
    input [15:0] writedata,
    output irq,
    output reg [15:0] readdata
);

// Register addresses
localparam ADDR_PERIOD_L = 3'h0;
localparam ADDR_PERIOD_H = 3'h1;
localparam ADDR_CONTROL = 3'h2;
localparam ADDR_STATUS = 3'h3;
localparam ADDR_SNAPSHOT_L = 3'h4;
localparam ADDR_SNAPSHOT_H = 3'h5;

// Control register bits
localparam CTRL_START = 0;
localparam CTRL_STOP = 1;
localparam CTRL_INT_EN = 2;
localparam CTRL_CONT_MODE = 3;
localparam CTRL_SNAPSHOT = 4;

// Status register bits
localparam STATUS_RUNNING = 0;
localparam STATUS_TIMEOUT = 1;

// Internal registers
reg [15:0] period_l_register;
reg [15:0] period_h_register;
reg [15:0] control_register;
reg [15:0] status_register;
reg [15:0] snapshot_l_register;
reg [15:0] snapshot_h_register;

// Internal counter
reg [31:0] internal_counter;

// Internal signals
reg running;
reg timeout_latch;
reg [31:0] snapshot_value;

// Write strobes
wire period_l_wr_strobe = chipselect && !write_n && (address == ADDR_PERIOD_L);
wire period_h_wr_strobe = chipselect && !write_n && (address == ADDR_PERIOD_H);
wire control_wr_strobe = chipselect && !write_n && (address == ADDR_CONTROL);

// Control signals from control register
wire start_strobe = control_wr_strobe && writedata[CTRL_START];
wire stop_strobe = control_wr_strobe && writedata[CTRL_STOP];
wire snapshot_strobe = control_wr_strobe && writedata[CTRL_SNAPSHOT];
wire int_enable = control_register[CTRL_INT_EN];
wire continuous_mode = control_register[CTRL_CONT_MODE];

// Status signals
wire counter_zero = (internal_counter == 32'h0);

// Interrupt generation
assign irq = timeout_latch && int_enable;

// Counter operation
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        // Asynchronous reset initialization
        period_l_register <= 16'd61567;
        period_h_register <= 16'd762;
        control_register <= 16'h0;
        status_register <= 16'h0;
        snapshot_l_register <= 16'h0;
        snapshot_h_register <= 16'h0;
        internal_counter <= 32'h02FA_F07F;  // Default counter value
        running <= 1'b0;
        timeout_latch <= 1'b0;
        snapshot_value <= 32'h0;
    end else begin
        // Register writes
        if (period_l_wr_strobe) begin
            period_l_register <= writedata;
        end
        
        if (period_h_wr_strobe) begin
            period_h_register <= writedata;
        end
        
        if (control_wr_strobe) begin
            control_register <= writedata;
            // Clear strobe bits after use
            control_register[CTRL_START] <= 1'b0;
            control_register[CTRL_STOP] <= 1'b0;
            control_register[CTRL_SNAPSHOT] <= 1'b0;
        end
        
        // Snapshot capture
        if (snapshot_strobe) begin
            snapshot_value <= internal_counter;
            snapshot_l_register <= internal_counter[15:0];
            snapshot_h_register <= internal_counter[31:16];
        end
        
        // Start/Stop control
        if (start_strobe) begin
            running <= 1'b1;
            // Reload counter on start
            internal_counter <= {period_h_register, period_l_register};
            timeout_latch <= 1'b0;
        end else if (stop_strobe) begin
            running <= 1'b0;
        end
        
        // Counter decrement
        if (running) begin
            if (counter_zero) begin
                timeout_latch <= 1'b1;
                if (continuous_mode) begin
                    // Auto-reload in continuous mode
                    internal_counter <= {period_h_register, period_l_register};
                end else begin
                    running <= 1'b0;
                end
            end else begin
                internal_counter <= internal_counter - 32'h1;
            end
        end
        
        // Update status register
        status_register[STATUS_RUNNING] <= running;
        status_register[STATUS_TIMEOUT] <= timeout_latch;
        
        // Clear timeout latch when reading status
        if (chipselect && !write_n && (address == ADDR_STATUS)) begin
            timeout_latch <= 1'b0;
        end
    end
end

// Read data multiplexer
always @(*) begin
    case (address)
        ADDR_PERIOD_L: readdata = period_l_register;
        ADDR_PERIOD_H: readdata = period_h_register;
        ADDR_CONTROL: readdata = control_register;
        ADDR_STATUS: readdata = status_register;
        ADDR_SNAPSHOT_L: readdata = snapshot_l_register;
        ADDR_SNAPSHOT_H: readdata = snapshot_h_register;
        default: readdata = 16'h0;
    endcase
end

endmodule
