module configurable_system_timer_50m (
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
  reg [15:0] period_l_register;
  reg [15:0] period_h_register;
  reg [31:0] internal_counter;
  reg [31:0] counter_snapshot;
  reg [3:0] control_register;
  reg [3:0] status_register;
  
  // Internal signals
  wire [31:0] counter_load_value;
  reg counter_is_running;
  wire counter_is_zero;
  reg timeout_occurred;
  reg timeout_occurred_delayed;
  
  // Write strobes
  wire period_h_wr_strobe;
  wire period_l_wr_strobe;
  wire control_wr_strobe;
  wire snap_h_wr_strobe;
  wire snap_l_wr_strobe;
  wire status_wr_strobe;
  
  // Control register bits
  wire interrupt_enabled = control_register[0];
  wire continuous_mode = control_register[1];
  wire start_strobe = control_register[2];
  wire stop_strobe = control_register[3];
  
  // Status register bits
  wire timeout_status = status_register[0];
  
  // Counter zero detection
  assign counter_is_zero = (internal_counter == 32'd0);
  
  // Counter load value
  assign counter_load_value = {period_h_register, period_l_register};
  
  // Write strobe generation
  assign period_h_wr_strobe = chipselect && !write_n && (address == 3'b000);
  assign period_l_wr_strobe = chipselect && !write_n && (address == 3'b001);
  assign control_wr_strobe = chipselect && !write_n && (address == 3'b010);
  assign snap_h_wr_strobe = chipselect && !write_n && (address == 3'b011);
  assign snap_l_wr_strobe = chipselect && !write_n && (address == 3'b100);
  assign status_wr_strobe = chipselect && !write_n && (address == 3'b101);
  
  // Counter running state machine
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      counter_is_running <= 1'b0;
    end else begin
      if (stop_strobe) begin
        counter_is_running <= 1'b0;
      end else if (start_strobe) begin
        counter_is_running <= 1'b1;
      end else if (counter_is_zero && !continuous_mode) begin
        counter_is_running <= 1'b0;
      end
    end
  end
  
  // Internal counter logic
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      internal_counter <= 32'h02FA_F07F;
    end else begin
      if (period_h_wr_strobe || period_l_wr_strobe) begin
        // Reload counter when period registers are written
        internal_counter <= counter_load_value;
      end else if (counter_is_running) begin
        if (counter_is_zero) begin
          internal_counter <= counter_load_value;
        end else begin
          internal_counter <= internal_counter - 32'd1;
        end
      end
    end
  end
  
  // Period registers
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      period_l_register <= 16'd61567;
      period_h_register <= 16'd762;
    end else begin
      if (period_l_wr_strobe) begin
        period_l_register <= writedata[15:0];
      end
      if (period_h_wr_strobe) begin
        period_h_register <= writedata[15:0];
      end
    end
  end
  
  // Control register
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      control_register <= 4'b0;
    end else if (control_wr_strobe) begin
      control_register <= writedata[3:0];
    end
  end
  
  // Status register and timeout detection
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      status_register <= 4'b0;
      timeout_occurred <= 1'b0;
      timeout_occurred_delayed <= 1'b0;
    end else begin
      // Delay timeout_occurred for edge detection
      timeout_occurred_delayed <= timeout_occurred;
      
      // Detect timeout event (counter reaches zero while running)
      if (counter_is_zero && counter_is_running) begin
        timeout_occurred <= 1'b1;
      end else begin
        timeout_occurred <= 1'b0;
      end
      
      // Update status register
      if (status_wr_strobe) begin
        // Clear timeout status when written
        status_register[0] <= 1'b0;
      end else if (timeout_occurred && !timeout_occurred_delayed) begin
        // Set timeout status on rising edge of timeout
        status_register[0] <= 1'b1;
      end
    end
  end
  
  // Counter snapshot logic
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      counter_snapshot <= 32'b0;
    end else begin
      if (snap_h_wr_strobe) begin
        counter_snapshot[31:16] <= internal_counter[31:16];
      end
      if (snap_l_wr_strobe) begin
        counter_snapshot[15:0] <= internal_counter[15:0];
      end
    end
  end
  
  // Interrupt generation
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      irq <= 1'b0;
    end else begin
      if (timeout_occurred && interrupt_enabled) begin
        irq <= 1'b1;
      end else begin
        irq <= 1'b0;
      end
    end
  end
  
  // Read data multiplexer
  always @(*) begin
    case (address)
      3'b000: readdata = {16'b0, period_h_register};
      3'b001: readdata = {16'b0, period_l_register};
      3'b010: readdata = {28'b0, control_register};
      3'b011: readdata = {16'b0, counter_snapshot[31:16]};
      3'b100: readdata = {16'b0, counter_snapshot[15:0]};
      3'b101: readdata = {28'b0, status_register};
      3'b110: readdata = internal_counter[31:16];
      3'b111: readdata = internal_counter[15:0];
      default: readdata = 32'b0;
    endcase
  end

endmodule
