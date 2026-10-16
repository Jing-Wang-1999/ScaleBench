module configurable_system_timer_50k_b (
    input  [31:0] address,
    input         chipselect,
    input         clk,
    input         reset_n,
    input         write_n,
    input  [31:0] writedata,
    output        irq,
    output [31:0] readdata
);

    // ------------------------------------------------------------------------
    // Internal Registers and Wires
    // ------------------------------------------------------------------------
    
    // Period Registers
    reg [15:0] period_l_register;
    reg [15:0] period_h_register;
    
    // Control Register Bits
    reg control_interrupt_enable;
    reg control_continuous_mode;
    
    // Status Register Bits
    reg status_timeout;
    
    // Counter and Snapshot
    reg [31:0] internal_counter;
    reg [31:0] snapshot_register;
    
    // Control Strobes (Derived from write operations)
    wire period_write_strobe;
    wire control_write_strobe;
    wire status_write_strobe;
    wire snap_l_wr_strobe;
    wire snap_h_wr_strobe;
    
    // Internal Control Signals
    wire force_reload;
    wire start_strobe;
    wire stop_strobe;
    wire counter_is_zero;
    wire timeout_event;
    
    // Delayed zero detection for edge detection
    reg delayed_unxcounter_is_zeroxx0;

    // ------------------------------------------------------------------------
    // Address Decoding and Write Strobes
    // ------------------------------------------------------------------------
    
    // Assuming a word-aligned map where lower 2 bits are ignored or part of byte enable logic not shown.
    // We assume address[1:0] == 0 for 32-bit accesses based on typical Avalon-like interfaces.
    // If byte enables were present, we would mask them. Here we assume full 32-bit writes.
    
    assign period_write_strobe = chipselect && !write_n && (address[3:0] == 4'h0); // Offset 0x0
    assign control_write_strobe = chipselect && !write_n && (address[3:0] == 4'h4); // Offset 0x4
    assign status_write_strobe  = chipselect && !write_n && (address[3:0] == 4'h8); // Offset 0x8
    assign snap_l_wr_strobe     = chipselect && !write_n && (address[3:0] == 4'hC); // Offset 0xC (Trigger snapshot low)
    assign snap_h_wr_strobe     = chipselect && !write_n && (address[3:0] == 4'hD); // Offset 0xD (Trigger snapshot high - hypothetical distinct addr or same)
    
    // Force reload occurs on period write or explicit force condition (mapped to control write bit 31 perhaps? 
    // Spec says: "any write strobe to these registers [period] will also trigger a force reload".
    // We will also assume a specific bit in control or a dedicated mechanism isn't needed beyond period writes 
    // unless specified. The prompt mentions "force_reload" as a signal controlling the counter.
    // Let's map force_reload to be active if period_write_strobe is high OR if a specific control bit is set.
    // However, strictly following "any write strobe to these registers will also trigger a force reload":
    assign force_reload = period_write_strobe; 

    // Start/Stop Strobes derivation
    // Usually mapped to control register bits. 
    // Let's assume writedata[0] = Start, writedata[1] = Stop when writing to Control?
    // Or dedicated addresses? The prompt lists them as signals. 
    // Given the interface only has address/data, these must be derived from writes to the Control Register.
    // Assumption: Control Register Write: Bit 0 = Start Strobe, Bit 1 = Stop Strobe.
    assign start_strobe = control_write_strobe && writedata[0];
    assign stop_strobe  = control_write_strobe && writedata[1];

    // ------------------------------------------------------------------------
    // Register Write Logic
    // ------------------------------------------------------------------------
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            period_l_register <= 16'd49999; // 0xC34F = 49999
            period_h_register <= 16'd0;
            control_interrupt_enable <= 1'b0;
            control_continuous_mode  <= 1'b0;
            status_timeout           <= 1'b0;
        end else begin
            // Period Registers
            if (period_write_strobe) begin
                period_l_register <= writedata[15:0];
                period_h_register <= writedata[31:16];
            end
            
            // Control Register
            if (control_write_strobe) begin
                control_interrupt_enable <= writedata[0];
                control_continuous_mode  <= writedata[1];
                // Note: Start/Stop are strobes, handled in counter logic, not stored as state bits usually,
                // unless the register reflects 'running' state. We'll keep running state separate.
            end
            
            // Status Register (Write to clear)
            if (status_write_strobe) begin
                // Typically writing 1 clears the interrupt. 
                // If writedata[0] is 1, clear timeout.
                if (writedata[0])
                    status_timeout <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Snapshot Logic
    // ------------------------------------------------------------------------
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            snapshot_register <= 32'd0;
        end else begin
            // Capture current counter value on snapshot strobes
            if (snap_l_wr_strobe || snap_h_wr_strobe) begin
                snapshot_register <= internal_counter;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Counter Logic
    // ------------------------------------------------------------------------
    
    assign counter_is_zero = (internal_counter == 32'd0);
    
    // Timeout event: Transition from non-zero to zero.
    // We need to detect the edge. 
    // delayed_unxcounter_is_zeroxx0 holds the zero status of the previous cycle.
    assign timeout_event = (!delayed_unxcounter_is_zeroxx0 && counter_is_zero);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            internal_counter <= 32'h0000_C34F;
            delayed_unxcounter_is_zeroxx0 <= 1'b1; // Initialize to 1 so we don't trigger timeout immediately on release if counter starts at 0? 
                                                   // But reset sets to C34F (non-zero). So next cycle delayed will be 0.
        end else begin
            // Update delayed zero flag
            delayed_unxcounter_is_zeroxx0 <= counter_is_zero;
            
            // Reload Condition
            if (force_reload || (counter_is_zero && !control_continuous_mode && timeout_event)) begin
                // Actually, if we are at zero and not continuous, we stop. 
                // The reload happens if force_reload is high OR if we just hit zero and need to restart (continuous) 
                // OR if force reload is asserted.
                // Specification: "If the counter reaches zero or a force reload condition occurs, the counter reloads..."
                // But also: "It stops either due to a stop signal or when the counter reaches zero in non-continuous mode."
                // This implies:
                // 1. Force Reload -> Reload value, keep running? (Usually yes).
                // 2. Hit Zero + Continuous -> Reload value, keep running.
                // 3. Hit Zero + Non-Continuous -> Reload value (?), then Stop? Or just Stop at 0?
                // Standard timer behavior: Reload happens, then if non-continuous, the 'run' enable is cleared.
                
                internal_counter <= {period_h_register, period_l_register};
            end 
            else if (start_strobe) begin
                // If start strobe received, ensure we have a valid count if currently zero
                if (counter_is_zero)
                    internal_counter <= {period_h_register, period_l_register};
            end
            else if (!counter_is_zero) begin
                // Decrement if running and not zero
                // We need a 'running' state. 
                // Let's infer running state: Running if (start_strobe) or (running && !stop && !zero_in_non_cont)
                // To simplify, we decrement if we are not stopped.
                // How do we track 'stopped'? 
                // Let's use a 'run' flip-flop.
                internal_counter <= internal_counter - 1'b1;
            end
            // Else hold at 0
        end
    end

    // Running State Machine
    reg counter_running;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            counter_running <= 1'b0;
        end else begin
            if (start_strobe) begin
                counter_running <= 1'b1;
            end else if (stop_strobe) begin
                counter_running <= 1'b0;
            end else if (timeout_event && !control_continuous_mode) begin
                // Stop automatically on timeout if not continuous
                counter_running <= 1'b0;
            end
            // Note: force_reload does not necessarily stop the counter, just resets value.
            // If counter was stopped, force_reload usually doesn't start it unless start_strobe is also present.
            // However, spec says "continuously decrements... when the counter is running".
        end
    end

    // Corrected Counter Decrement Logic incorporating 'counter_running'
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            internal_counter <= 32'h0000_C34F;
            delayed_unxcounter_is_zeroxx0 <= 1'b1;
        end else begin
            // Update delayed zero flag based on current counter BEFORE update? 
            // No, based on counter value at start of cycle to detect edge next cycle.
            delayed_unxcounter_is_zeroxx0 <= (internal_counter == 32'd0);
            
            // Determine Next Counter Value
            if (force_reload) begin
                internal_counter <= {period_h_register, period_l_register};
            end else if (counter_running) begin
                if (internal_counter == 32'd0) begin
                    // Hit zero while running
                    if (control_continuous_mode) begin
                        internal_counter <= {period_h_register, period_l_register};
                    end else begin
                        // Non-continuous: Stay at 0, state machine will clear 'running'
                        internal_counter <= 32'd0;
                    end
                end else begin
                    internal_counter <= internal_counter - 1'b1;
                end
            end else begin
                // Not running, hold value (unless force reload handled above)
                // If start_strobe happens, we might need to load if zero.
                // But start_strobe sets 'counter_running'. The decrement happens next cycle?
                // Or immediately? Usually immediately if we load.
                if (start_strobe && internal_counter == 32'd0) begin
                     internal_counter <= {period_h_register, period_l_register};
                end
                // Else hold
            end
        end
    end

    // ------------------------------------------------------------------------
    // Interrupt Logic
    // ------------------------------------------------------------------------
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            status_timeout <= 1'b0;
        end else begin
            if (timeout_event) begin
                status_timeout <= 1'b1;
            end else if (status_write_strobe && writedata[0]) begin
                status_timeout <= 1'b0;
            end
        end
    end

    assign irq = status_timeout && control_interrupt_enable;

    // ------------------------------------------------------------------------
    // Read Data Multiplexing
    // ------------------------------------------------------------------------
    
    reg [31:0] readdata_reg;
    
    always @(*) begin
        case (address[3:0])
            4'h0: begin // Period Register
                readdata_reg = {period_h_register, period_l_register};
            end
            4'h4: begin // Control Register
                // Map internal state to read data
                // Bit 0: Interrupt Enable
                // Bit 1: Continuous Mode
                // Bit 2: Running Status (Optional but useful)
                readdata_reg = {30'd0, counter_running, control_continuous_mode, control_interrupt_enable};
            end
            4'h8: begin // Status Register
                // Bit 0: Timeout
                readdata_reg = {31'd0, status_timeout};
            end
            4'hC, 4'hD: begin // Snapshot Register
                readdata_reg = snapshot_register;
            end
            default: begin
                readdata_reg = 32'd0;
            end
        endcase
    end
    
    assign readdata = chipselect ? readdata_reg : 32'd0;

endmodule
