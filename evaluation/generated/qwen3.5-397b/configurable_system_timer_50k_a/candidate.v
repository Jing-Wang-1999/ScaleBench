module configurable_system_timer_50k_a (
    input  [2:0]  address,
    input         chipselect,
    input         clk,
    input         reset_n,
    input         write_n,
    input  [15:0] writedata,
    output        irq,
    output [15:0] readdata
);

    // ------------------------------------------------------------------------
    // Internal Registers and Wires
    // ------------------------------------------------------------------------
    
    // 32-bit Counter
    reg [31:0] internal_counter;
    
    // Period Registers (Load Value)
    reg [15:0] period_l_register;
    reg [15:0] period_h_register;
    
    // Control Register
    // Bit 0: Start Strobe (Write 1 to start)
    // Bit 1: Stop Strobe (Write 1 to stop)
    // Bit 2: Continuous Mode (1 = auto-reload)
    // Bit 3: Interrupt Enable
    reg [3:0]  control_register;
    
    // Timeout State
    reg        timeout_occurred;
    reg        timeout_occurred_dly; // For debouncing/edge detection logic if needed, though latch is primary
    
    // Write Strobes
    wire       write_period_l;
    wire       write_period_h;
    wire       write_control;
    
    // Control Bits
    wire       ctrl_start;
    wire       ctrl_stop;
    wire       ctrl_continuous;
    wire       ctrl_int_enable;
    
    // Running State
    reg        timer_running;
    
    // Snapshot Register (Captures counter on read of snapshot address if implemented, 
    // but spec says readdata muxes current counter. We'll implement a snapshot register 
    // if address maps to it, otherwise just pass through. 
    // Based on typical Avalon-like timers: 
    // Addr 0: Status/Control? Or Period? 
    // Let's define a standard map based on the description:
    // The prompt implies specific registers: period_h, period_l, control, and current counter.
    // We need to map address [2:0] to these.
    // Common mapping for such timers:
    // 0: Status (or Control readback)
    // 1: Control (Write)
    // 2: Period Low
    // 3: Period High
    // 4: Counter Low (Snapshot/Current)
    // 5: Counter High (Snapshot/Current)
    // However, the prompt says "readdata is multiplexed based on address".
    // Let's assume a safe mapping that covers all described entities.
    // Address 0: Control Register (Read/Write)
    // Address 1: Period Low (Read/Write)
    // Address 2: Period High (Read/Write)
    // Address 3: Counter Low (Read Only)
    // Address 4: Counter High (Read Only)
    // Address 5: Snapshot Low (Read Only - captured value)
    // Address 6: Snapshot High (Read Only - captured value)
    // Address 7: Reserved or Status
    
    // To be safe and strictly follow "multiplexed based on address", we will implement
    // the read mux for the known registers.
    
    // Snapshot logic: Usually captures the counter value when the snapshot register is accessed
    // or continuously tracks. The prompt mentions "snapshot values". 
    // We will implement a snapshot register that updates when the timer stops or on specific access?
    // Re-reading: "readdata is multiplexed ... allowing access to ... snapshot values".
    // Simplest robust implementation: Snapshot registers hold the value of the counter 
    // at the moment the timer stops or when explicitly latched. 
    // Given the simplicity required, we will make the snapshot registers track the counter 
    // when not running, or just map the current counter to the "Counter" addresses and 
    // have dedicated snapshot registers that latch on Stop or Timeout.
    // Let's latch snapshot on Stop or Timeout for stability.
    
    reg [31:0] snapshot_register;
    reg        snapshot_valid;

    // ------------------------------------------------------------------------
    // Write Strobes Generation
    // ------------------------------------------------------------------------
    
    assign write_period_l = chipselect && !write_n && (address == 3'd1);
    assign write_period_h = chipselect && !write_n && (address == 3'd2);
    assign write_control  = chipselect && !write_n && (address == 3'd0);

    // Control Bit Extraction
    assign ctrl_start     = control_register[0];
    assign ctrl_stop      = control_register[1];
    assign ctrl_continuous= control_register[2];
    assign ctrl_int_enable= control_register[3];

    // ------------------------------------------------------------------------
    // Sequential Logic (Registers)
    // ------------------------------------------------------------------------
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Reset Values as specified
            internal_counter  <= 32'h0000_C34F; // 50000 - 1 = 49999 (0xC34F)
            period_l_register <= 16'd49999;
            period_h_register <= 16'd0;
            control_register  <= 4'd0;
            timeout_occurred  <= 1'b0;
            timer_running     <= 1'b0;
            snapshot_register <= 32'h0000_C34F;
        end else begin
            // -------------------------------------------------------------
            // Control Register Handling
            // -------------------------------------------------------------
            if (write_control) begin
                // Write new control value, but handle strobes immediately
                // We store the bits. The strobe bits (0 and 1) are typically write-1-to-act
                // and then cleared, or they represent state. 
                // Prompt: "start_strobe bit starts... stop_strobe bit stops".
                // Usually, these are self-clearing or level sensitive in the control reg.
                // Let's assume the register holds the configuration (continuous, int_en) 
                // and the strobes are actions.
                
                // Update configuration bits (2 and 3) directly from writedata
                control_register[3:2] <= writedata[3:2];
                
                // Handle Strobes (Actions)
                if (writedata[0]) begin // Start Strobe
                    timer_running <= 1'b1;
                    // Clear timeout on start? Usually yes, to re-arm interrupt
                    timeout_occurred <= 1'b0; 
                end
                if (writedata[1]) begin // Stop Strobe
                    timer_running <= 1'b0;
                    // Capture snapshot on stop
                    snapshot_register <= internal_counter;
                end
                // Bits 0 and 1 in the stored register might be kept as 0 or reflect status.
                // Let's keep them 0 in the stored reg if they are pure strobes, 
                // or reflect the last command. Standard practice: clear strobes after action.
                control_register[1:0] <= 2'd0;
            end
            
            // -------------------------------------------------------------
            // Period Registers Handling
            // -------------------------------------------------------------
            if (write_period_l) begin
                period_l_register <= writedata;
                // Prompt: "timer reloads the counter when a write strobe is asserted on period_h/l"
                // If running, do we reload immediately? Usually yes, or on next cycle.
                // "The timer reloads the counter when a write strobe is asserted..."
                internal_counter <= {period_h_register, writedata};
                // Also clear timeout if we are reloading manually?
                // timeout_occurred <= 1'b0; 
            end
            
            if (write_period_h) begin
                period_h_register <= writedata;
                // Reload counter with new high and existing low
                internal_counter <= {writedata, period_l_register};
            end
            
            // If both written in same cycle (unlikely with single port, but logically):
            // The order above matters. If address decoding prevents simultaneous writes, fine.
            // If simultaneous, we need a combined reload. 
            // Since address is unique per cycle, only one write happens per cycle.
            
            // -------------------------------------------------------------
            // Timer Countdown Logic
            // -------------------------------------------------------------
            if (timer_running) begin
                if (internal_counter == 32'd0) begin
                    // Timeout Event
                    timeout_occurred <= 1'b1;
                    
                    if (ctrl_continuous) begin
                        // Reload and continue
                        internal_counter <= {period_h_register, period_l_register};
                        // Note: In continuous mode, timeout_occurred might pulse or stay high.
                        // Prompt: "debounced zero-detect mechanism ensures a single timeout event per countdown cycle"
                        // We keep timeout_occurred high until cleared by start or read?
                        // Usually, interrupt is cleared by writing to control or status.
                        // Here, we'll keep it high until explicitly cleared or restarted.
                        // But if continuous, do we generate interrupt every cycle?
                        // "single timeout event per countdown cycle".
                        // So if we reload, we are in a new cycle. 
                        // We need to ensure the interrupt doesn't stick forever if not cleared.
                        // However, without a specific "clear interrupt" bit, we might rely on 
                        // the edge detection or clearing on start.
                        // Let's hold timeout_occurred high until the counter runs away from 0 
                        // or is cleared by software (start strobe).
                        // To ensure "single event", we can use a flag that clears when counter != 0.
                        // But if continuous reloads immediately, counter is never != 0 at clock edge?
                        // It reloads to Period. So next cycle counter = Period.
                        // So timeout_occurred will be high for 1 cycle if we clear it when reloading?
                        // Let's set timeout_occurred high, and clear it when the counter is reloaded (next cycle).
                        // Actually, simpler: Set timeout_occurred when hitting 0. 
                        // Clear it when the timer is started (re-armed) or if we want edge, clear it automatically?
                        // "ensures a single timeout event per countdown cycle" -> Latch it.
                        // We will leave it latched until software clears it (via Start Strobe or similar).
                        // But if continuous, we need to allow the next interrupt.
                        // Strategy: Latch timeout. If continuous, the hardware automatically clears the latch 
                        // after the reload is effective? No, that would miss the interrupt.
                        // Standard: Latch timeout. Software must clear it. If continuous, the hardware 
                        // generates a new timeout when it hits 0 again. If software hasn't cleared, 
                        // it stays high. That's fine.
                    end else begin
                        // One-shot mode: Stop timer
                        timer_running <= 1'b0;
                        snapshot_register <= internal_counter; // 0
                    end
                end else begin
                    internal_counter <= internal_counter - 1'b1;
                end
            end
            
            // If not running, counter holds value (unless written via period regs)
            
            // Optional: Clear timeout if software reads status? 
            // No explicit read-clear mentioned. We rely on Start Strobe to clear.
            
        end
    end

    // ------------------------------------------------------------------------
    // Output Logic
    // ------------------------------------------------------------------------
    
    // IRQ Generation
    // Asserted when timeout occurred AND interrupt is enabled
    assign irq = timeout_occurred && ctrl_int_enable;
    
    // Read Data Multiplexer
    reg [15:0] readdata_reg;
    
    always @(*) begin
        case (address)
            3'd0: begin
                // Control Register Readback
                // Return current config + status bits?
                // Let's return: {Reserved, IntEn, Continuous, StopStrobeStatus, StartStrobeStatus}
                // Or just the config bits and timeout status?
                // Common: Bit 0 = Timeout Status (RO), Bit 1 = Running (RO), Bit 2=Cont, Bit 3=IntEn
                // But the prompt says control_register has start/stop strobes.
                // Let's map read of addr 0 to: {12'd0, ctrl_int_enable, ctrl_continuous, timeout_occurred, timer_running}
                // Or strictly the control_register content?
                // "access to ... control register state"
                // Let's return the control bits and the timeout status in the lower bits.
                // Map: [3] IntEn, [2] Continuous, [1] Running (Status), [0] Timeout (Status)
                // This is a common pattern.
                readdata_reg = {12'd0, control_register[3:2], timer_running, timeout_occurred};
            end
            3'd1: begin
                // Period Low
                readdata_reg = period_l_register;
            end
            3'd2: begin
                // Period High
                readdata_reg = period_h_register;
            end
            3'd3: begin
                // Counter Low (Current)
                readdata_reg = internal_counter[15:0];
            end
            3'd4: begin
                // Counter High (Current)
                readdata_reg = internal_counter[31:16];
            end
            3'd5: begin
                // Snapshot Low
                readdata_reg = snapshot_register[15:0];
            end
            3'd6: begin
                // Snapshot High
                readdata_reg = snapshot_register[31:16];
            end
            default: begin
                readdata_reg = 16'd0;
            end
        endcase
    end
    
    assign readdata = readdata_reg;

endmodule
