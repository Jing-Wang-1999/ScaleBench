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
reg [15:0] snap_l_register;
reg [15:0] snap_h_register;
reg control_continuous;
reg control_interrupt_enable;
reg status_timeout;
reg counter_running;

// Internal signals
wire counter_is_zero;
reg delayed_counter_is_zero;
wire timeout_event;
wire force_reload_condition;
reg force_reload;
reg start_strobe;
reg stop_strobe;
reg period_l_wr_strobe;
reg period_h_wr_strobe;
reg snap_l_wr_strobe;
reg snap_h_wr_strobe;
reg control_wr_strobe;
reg status_wr_strobe;

// Address decoding
localparam [2:0] ADDR_STATUS     = 3'h0;
localparam [2:0] ADDR_CONTROL    = 3'h1;
localparam [2:0] ADDR_PERIOD_L   = 3'h2;
localparam [2:0] ADDR_PERIOD_H   = 3'h3;
localparam [2:0] ADDR_SNAPSHOT_L = 3'h4;
localparam [2:0] ADDR_SNAPSHOT_H = 3'h5;

// Zero detection
assign counter_is_zero = (internal_counter == 32'h0);

// Timeout event detection
assign timeout_event = (~delayed_counter_is_zero & counter_is_zero);

// Force reload condition
assign force_reload_condition = force_reload | timeout_event;

// Write strobe generation
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        start_strobe <= 1'b0;
        stop_strobe <= 1'b0;
        period_l_wr_strobe <= 1'b0;
        period_h_wr_strobe <= 1'b0;
        snap_l_wr_strobe <= 1'b0;
        snap_h_wr_strobe <= 1'b0;
        control_wr_strobe <= 1'b0;
        status_wr_strobe <= 1'b0;
    end else begin
        // Default values
        start_strobe <= 1'b0;
        stop_strobe <= 1'b0;
        period_l_wr_strobe <= 1'b0;
        period_h_wr_strobe <= 1'b0;
        snap_l_wr_strobe <= 1'b0;
        snap_h_wr_strobe <= 1'b0;
        control_wr_strobe <= 1'b0;
        status_wr_strobe <= 1'b0;
        
        if (chipselect && !write_n) begin
            case (address)
                ADDR_CONTROL: begin
                    if (writedata[0]) start_strobe <= 1'b1;
                    if (writedata[1]) stop_strobe <= 1'b1;
                    if (writedata[2]) force_reload <= 1'b1;
                    control_wr_strobe <= 1'b1;
                end
                ADDR_STATUS: begin
                    status_wr_strobe <= 1'b1;
                end
                ADDR_PERIOD_L: begin
                    period_l_wr_strobe <= 1'b1;
                    force_reload <= 1'b1;
                end
                ADDR_PERIOD_H: begin
                    period_h_wr_strobe <= 1'b1;
                    force_reload <= 1'b1;
                end
                ADDR_SNAPSHOT_L: begin
                    snap_l_wr_strobe <= 1'b1;
                end
                ADDR_SNAPSHOT_H: begin
                    snap_h_wr_strobe <= 1'b1;
                end
            endcase
        end else begin
            force_reload <= 1'b0;
        end
    end
end

// Main counter logic
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        internal_counter <= 32'h0000C34F;
        counter_running <= 1'b0;
        delayed_counter_is_zero <= 1'b0;
    end else begin
        // Update delayed zero signal
        delayed_counter_is_zero <= counter_is_zero;
        
        // Handle force reload or timeout
        if (force_reload_condition) begin
            internal_counter <= {period_h_register, period_l_register};
            if (timeout_event) begin
                counter_running <= control_continuous;
            end else begin
                counter_running <= counter_running;
            end
        end
        // Handle normal decrement
        else if (counter_running && !counter_is_zero) begin
            internal_counter <= internal_counter - 1'b1;
        end
        
        // Handle start/stop strobes
        if (start_strobe) begin
            counter_running <= 1'b1;
        end
        if (stop_strobe) begin
            counter_running <= 1'b0;
        end
    end
end

// Period registers
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        period_l_register <= 16'd49999;
        period_h_register <= 16'd0;
    end else begin
        if (period_l_wr_strobe) begin
            period_l_register <= writedata[15:0];
        end
        if (period_h_wr_strobe) begin
            period_h_register <= writedata[15:0];
        end
    end
end

// Snapshot registers
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        snap_l_register <= 16'h0;
        snap_h_register <= 16'h0;
    end else begin
        if (snap_l_wr_strobe) begin
            snap_l_register <= internal_counter[15:0];
        end
        if (snap_h_wr_strobe) begin
            snap_h_register <= internal_counter[31:16];
        end
    end
end

// Control register
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        control_continuous <= 1'b0;
        control_interrupt_enable <= 1'b0;
    end else if (control_wr_strobe) begin
        control_continuous <= writedata[3];
        control_interrupt_enable <= writedata[4];
    end
end

// Status register and interrupt generation
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        status_timeout <= 1'b0;
        irq <= 1'b0;
    end else begin
        // Set timeout status on timeout event
        if (timeout_event) begin
            status_timeout <= 1'b1;
        end
        // Clear timeout status on write to status register
        if (status_wr_strobe && writedata[0]) begin
            status_timeout <= 1'b0;
        end
        
        // Generate interrupt
        if (timeout_event && control_interrupt_enable) begin
            irq <= 1'b1;
        end else if (status_wr_strobe && writedata[0]) begin
            irq <= 1'b0;
        end
    end
end

// Read data multiplexing
always @(*) begin
    case (address)
        ADDR_STATUS: begin
            readdata = {31'h0, status_timeout};
        end
        ADDR_CONTROL: begin
            readdata = {27'h0, control_interrupt_enable, control_continuous, 
                       counter_running, stop_strobe, start_strobe};
        end
        ADDR_PERIOD_L: begin
            readdata = {16'h0, period_l_register};
        end
        ADDR_PERIOD_H: begin
            readdata = {16'h0, period_h_register};
        end
        ADDR_SNAPSHOT_L: begin
            readdata = {16'h0, snap_l_register};
        end
        ADDR_SNAPSHOT_H: begin
            readdata = {16'h0, snap_h_register};
        end
        default: begin
            readdata = 32'h0;
        end
    endcase
end

endmodule
