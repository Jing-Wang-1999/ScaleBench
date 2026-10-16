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
  reg [31:0] internal_counter;
  reg [15:0] period_l_register;
  reg [15:0] period_h_register;
  reg [3:0] control_register;
  reg [31:0] counter_snapshot;

  // Internal signals
  wire [31:0] counter_load_value;
  wire counter_is_zero;
  reg counter_is_running;
  reg timeout_occurred;

  // Concatenate period registers to form the load value
  assign counter_load_value = {period_h_register, period_l_register};

  // Counter zero detection
  assign counter_is_zero = (internal_counter == 32'b0);

  // Write strobes
  wire period_h_wr_strobe = chipselect && ~write_n && (address == 3'b000);
  wire period_l_wr_strobe = chipselect && ~write_n && (address == 3'b001);
  wire control_wr_strobe  = chipselect && ~write_n && (address == 3'b010);
  wire snap_h_wr_strobe   = chipselect && ~write_n && (address == 3'b011);
  wire snap_l_wr_strobe   = chipselect && ~write_n && (address == 3'b100);
  wire status_wr_strobe   = chipselect && ~write_n && (address == 3'b101);

  // Asynchronous reset
  always @(negedge reset_n or posedge clk) begin
    if (!reset_n) begin
      internal_counter <= 32'h02FAF07F;
      period_l_register <= 16'd61567;
      period_h_register <= 16'd762;
      control_register <= 4'b0;
      counter_is_running <= 1'b0;
      timeout_occurred <= 1'b0;
      irq <= 1'b0;
    end else begin
      // Handle write strobes
      if (period_h_wr_strobe) begin
        period_h_register <= writedata[15:0];
      end
      if (period_l_wr_strobe) begin
        period_l_register <= writedata[15:0];
      end
      if (control_wr_strobe) begin
        control_register <= writedata[3:0];
      end
      if (snap_h_wr_strobe) begin
        counter_snapshot[31:16] <= internal_counter[31:16];
      end
      if (snap_l_wr_strobe) begin
        counter_snapshot[15:0] <= internal_counter[15:0];
      end
      if (status_wr_strobe) begin
        timeout_occurred <= writedata[0];
      end

      // Timer operation
      if (counter_is_running) begin
        if (counter_is_zero) begin
          internal_counter <= counter_load_value;
          timeout_occurred <= 1'b1;
          if (control_register[1] == 1'b0) begin
            counter_is_running <= 1'b0;
          end
        end else begin
          internal_counter <= internal_counter - 1;
        end
      end

      // Start/Stop control
      if (control_register[2]) begin
        counter_is_running <= 1'b1;
      end
      if (control_register[3]) begin
        counter_is_running <= 1'b0;
      end

      // Interrupt generation
      irq <= timeout_occurred && control_register[0];
    end
  end

  // Read data logic
  always @(*) begin
    case (address)
      3'b000: readdata = {16'b0, period_h_register};
      3'b001: readdata = {16'b0, period_l_register};
      3'b010: readdata = {28'b0, control_register};
      3'b011: readdata = counter_snapshot[31:16];
      3'b100: readdata = counter_snapshot[15:0];
      3'b101: readdata = {31'b0, timeout_occurred};
      default: readdata = 32'b0;
    endcase
  end

endmodule
