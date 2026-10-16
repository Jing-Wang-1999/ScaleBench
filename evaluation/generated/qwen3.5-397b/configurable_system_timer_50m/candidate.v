module configurable_system_timer_50m (
  input  [3:0] address,
  input        chipselect,
  input        clk,
  input        reset_n,
  input        write_n,
  input  [31:0] writedata,
  output       irq,
  output [31:0] readdata
);

  // --------------------------------------------------------------------------
  // Internal Registers
  // --------------------------------------------------------------------------
  reg [31:0] internal_counter;
  reg [15:0] period_l_register;
  reg [15:0] period_h_register;
  reg [3:0]  control_register;
  reg [31:0] counter_snapshot;
  reg        timeout_occurred;
  reg        counter_is_running;

  // --------------------------------------------------------------------------
  // Derived Signals
  // --------------------------------------------------------------------------
  wire [31:0] counter_load_value;
  wire        counter_is_zero;
  wire        period_h_wr_strobe;
  wire        period_l_wr_strobe;
  wire        control_wr_strobe;
  wire        snap_h_wr_strobe;
  wire        snap_l_wr_strobe;
  wire        status_wr_strobe;
  wire        reload_trigger;

  // Concatenate period registers to form the load value
  assign counter_load_value = {period_h_register, period_l_register};

  // Counter zero detection
  assign counter_is_zero = (internal_counter == 32'd0);

  // --------------------------------------------------------------------------
  // Write Strobes Generation
  // Active when chipselect is high, write_n is low (write cycle), and address matches
  // --------------------------------------------------------------------------
  assign period_h_wr_strobe = chipselect && !write_n && (address == 4'd0);
  assign period_l_wr_strobe = chipselect && !write_n && (address == 4'd1);
  assign control_wr_strobe  = chipselect && !write_n && (address == 4'd2);
  // Snapshot strobes: Writing to these addresses triggers a snapshot capture
  assign snap_h_wr_strobe   = chipselect && !write_n && (address == 4'd3);
  assign snap_l_wr_strobe   = chipselect && !write_n && (address == 4'd4);
  // Status strobe: Writing to this address can clear status/irq
  assign status_wr_strobe   = chipselect && !write_n && (address == 4'd5);

  // --------------------------------------------------------------------------
  // Control Logic Extraction
  // --------------------------------------------------------------------------
  // Bit 0: Interrupt Enable
  // Bit 1: Continuous Mode
  // Bit 2: Start Strobe
  // Bit 3: Stop Strobe
  wire interrupt_enable = control_register[0];
  wire continuous_mode  = control_register[1];
  wire start_strobe     = control_register[2];
  wire stop_strobe      = control_register[3];

  // --------------------------------------------------------------------------
  // Reload Trigger Logic
  // Reload happens when counter hits zero OR if forced by logic (e.g., initial start)
  // Here we reload on zero, or if the counter is not running and we just started.
  // However, spec says: "reloads ... when it reaches zero or if forced to reload."
  // We will handle the initial load on start separately or via the zero condition if we preload.
  // To ensure clean start, we reload when hitting zero.
  // If starting from stopped state, we might need to load immediately if counter is 0 or invalid.
  // Let's define reload_trigger primarily on zero.
  assign reload_trigger = counter_is_zero;

  // --------------------------------------------------------------------------
  // Sequential Logic: Registers and Counter
  // --------------------------------------------------------------------------
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Asynchronous Reset
      // Spec: internal_counter to 32'h02FA_F07F
      internal_counter   <= 32'h02FA_F07F;
      // Spec: period_l_register to 16'd61567
      period_l_register  <= 16'd61567;
      // Spec: period_h_register to 16'd762
      period_h_register  <= 16'd762;
      control_register   <= 4'd0;
      counter_snapshot   <= 32'd0;
      timeout_occurred   <= 1'b0;
      counter_is_running <= 1'b0;
    end else begin
      // Default assignments for non-write cycles to hold state
      // Period Registers Update
      if (period_h_wr_strobe)
        period_h_register <= writedata[15:0];
      
      if (period_l_wr_strobe)
        period_l_register <= writedata[15:0];

      // Control Register Update
      if (control_wr_strobe) begin
        control_register <= writedata[3:0];
        
        // Handle Start/Stop Strobes immediately upon write
        if (writedata[2]) // Start bit set
          counter_is_running <= 1'b1;
        if (writedata[3]) // Stop bit set
          counter_is_running <= 1'b0;
      end

      // Snapshot Logic
      // Capture current counter value when snapshot strobes occur
      if (snap_h_wr_strobe || snap_l_wr_strobe) begin
        counter_snapshot <= internal_counter;
      end

      // Status Register Update (Clear IRQ on write to status address)
      if (status_wr_strobe) begin
        timeout_occurred <= 1'b0;
      end

      // Counter Logic
      if (counter_is_running) begin
        if (counter_is_zero) begin
          // Reload value
          internal_counter <= counter_load_value;
          
          // Set Timeout Flag
          timeout_occurred <= 1'b1;
          
          // Handle Continuous Mode
          if (!continuous_mode) begin
            // Stop if not continuous
            counter_is_running <= 1'b0;
          end
          // If continuous, it keeps running and just reloaded
        end else begin
          // Decrement
          internal_counter <= internal_counter - 32'd1;
        end
      end else begin
        // If not running, check if we just received a start command via control register write
        // This case is handled above in the control_register write block.
        // However, if we are stopped and hit zero (shouldn't happen if stopped before zero), hold value.
        // One edge case: If started when counter is already 0, we need to reload immediately.
        // The logic above: if running and zero -> reload. 
        // If we transition from !running to running, and counter is 0, we need to reload.
        // Let's refine: If start_strobe is detected and counter is 0, force reload.
        // Since start_strobe is a pulse in the write block, we can check a local variable or restructure.
        // Simpler approach: If running and (zero OR (just_started AND zero)), reload.
        // To keep it clean: The spec says "reloads ... when it reaches zero". 
        // If we start at 0, we technically haven't "reached" zero from a count, but we are at zero.
        // Let's add a specific check: If running and counter_is_zero, reload. 
        // If we write Start and counter is 0, next cycle: running=1, zero=1 -> Reloads. Correct.
        
        // Hold value if not running
        internal_counter <= internal_counter;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Output Logic
  // --------------------------------------------------------------------------
  
  // IRQ Generation: Timeout occurred AND Interrupts enabled
  assign irq = timeout_occurred && interrupt_enable;

  // Read Data Multiplexer
  always @(*) begin
    case (address)
      4'd0: readdata = {16'd0, period_h_register};       // Period High
      4'd1: readdata = {16'd0, period_l_register};       // Period Low
      4'd2: readdata = {28'd0, control_register};        // Control
      4'd3: readdata = counter_snapshot;                 // Snapshot (Full 32-bit accessible via any snap addr? Usually mapped)
                                                         // Spec implies snap_h and snap_l strobes. 
                                                         // Let's map read addresses to match typical APB/Avalon style or just return snapshot.
                                                         // Assuming address 3 and 4 return parts of snapshot or full.
                                                         // Given 32-bit readdata, returning full snapshot on 3 and 4 is safe, 
                                                         // or split them. Let's return full snapshot on 3, and 4 for consistency or status.
      4'd4: readdata = counter_snapshot;                 // Snapshot alias or Low part? Let's return full for simplicity unless specified.
      4'd5: readdata = {31'd0, timeout_occurred};        // Status
      default: readdata = 32'd0;
    endcase
  end

endmodule
