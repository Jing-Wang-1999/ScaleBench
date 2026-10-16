module programmable_alarm_timer_50m (
    input  [3:0]  address,
    input         chipselect,
    input         clk,
    input         reset_n,
    input         write_n,
    input  [31:0] writedata,
    output        irq,
    output [31:0] readdata
);

    // ------------------------------------------------------------------------
    // Register Definitions
    // ------------------------------------------------------------------------
    
    // Period Registers (Configurable start value)
    reg [15:0] period_l_register;
    reg [15:0] period_h_register;

    // Control Register Bits
    reg        ctrl_start;      // Bit 0: Start counter
    reg        ctrl_stop;       // Bit 1: Stop counter
    reg        ctrl_int_enable; // Bit 2: Interrupt Enable
    reg        ctrl_cont_mode;  // Bit 3: Continuous Mode (Auto-reload)
    
    // Status Register Bits
    reg        status_timeout;  // Bit 0: Timeout occurred
    reg        status_running;  // Bit 1: Counter is running

    // Internal Counter (32-bit)
    reg [31:0] internal_counter;

    // Snapshot Register (Captures counter value for readback)
    reg [31:0] snapshot_register;

    // Strobe signals derived from control writes
    reg        start_strobe;
    reg        stop_strobe;
    reg        period_l_wr_strobe;
    reg        period_h_wr_strobe;

    // ------------------------------------------------------------------------
    // Address Map
    // ------------------------------------------------------------------------
    // 0: Period Low (Write), Snapshot Low (Read) - Assumed based on typical Avalon-like maps
    // 1: Period High (Write), Snapshot High (Read)
    // 2: Control (Write), Status (Read)
    // 3: Reserved or direct Counter Read (Implemented as Counter Read for completeness)
    
    localparam ADDR_PERIOD_L = 4'd0;
    localparam ADDR_PERIOD_H = 4'd1;
    localparam ADDR_CTRL     = 4'd2;
    localparam ADDR_SNAP_L   = 4'd0; // Read alias
    localparam ADDR_SNAP_H   = 4'd1; // Read alias
    localparam ADDR_STATUS   = 4'd2; // Read alias
    localparam ADDR_COUNT_L  = 4'd3; // Direct counter read low
    localparam ADDR_COUNT_H  = 4'd4; // Direct counter read high (if addressed)

    // ------------------------------------------------------------------------
    // Asynchronous Reset & Synchronous Logic
    // ------------------------------------------------------------------------

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Initialization per specification
            internal_counter   <= 32'h02FA_F07F;
            period_l_register  <= 16'd61567;
            period_h_register  <= 16'd762;
            
            ctrl_start         <= 1'b0;
            ctrl_stop          <= 1'b0;
            ctrl_int_enable    <= 1'b0;
            ctrl_cont_mode     <= 1'b0;
            
            status_timeout     <= 1'b0;
            status_running     <= 1'b0;
            
            snapshot_register  <= 32'h02FA_F07F;
            
            start_strobe       <= 1'b0;
            stop_strobe        <= 1'b0;
            period_l_wr_strobe <= 1'b0;
            period_h_wr_strobe <= 1'b0;
        end
        else begin
            // --------------------------------------------------------------
            // 1. Input Decoding & Strobe Generation
            // --------------------------------------------------------------
            // Strobess are high for one clock cycle when a write occurs to specific addresses
            period_l_wr_strobe <= (chipselect && !write_n && (address == ADDR_PERIOD_L));
            period_h_wr_strobe <= (chipselect && !write_n && (address == ADDR_PERIOD_H));
            
            // Control register writes
            if (chipselect && !write_n && (address == ADDR_CTRL)) begin
                ctrl_start      <= writedata[0];
                ctrl_stop       <= writedata[1];
                ctrl_int_enable <= writedata[2];
                ctrl_cont_mode  <= writedata[3];
                
                // Generate strobes for start/stop actions based on write
                start_strobe <= writedata[0];
                stop_strobe  <= writedata[1];
            end
            else begin
                start_strobe <= 1'b0;
                stop_strobe  <= 1'b0;
            end

            // --------------------------------------------------------------
            // 2. Period Register Updates
            // --------------------------------------------------------------
            if (period_l_wr_strobe)
                period_l_register <= writedata[15:0];
            
            if (period_h_wr_strobe)
                period_h_register <= writedata[15:0];

            // --------------------------------------------------------------
            // 3. Control State Machine (Start/Stop)
            // --------------------------------------------------------------
            if (stop_strobe) begin
                status_running <= 1'b0;
            end
            else if (start_strobe) begin
                status_running <= 1'b0; // Ensure stopped before reload/start sequence if needed, 
                                        // but typically start implies reload then run.
                // Immediate reload on start
                internal_counter <= {period_h_register, period_l_register};
                status_timeout   <= 1'b0; // Clear timeout on restart
                status_running   <= 1'b1;
            end

            // --------------------------------------------------------------
            // 4. Counter Operation
            // --------------------------------------------------------------
            if (status_running) begin
                if (internal_counter == 32'd0) begin
                    // Timeout reached
                    status_timeout <= 1'b1;
                    
                    if (ctrl_cont_mode) begin
                        // Auto-reload
                        internal_counter <= {period_h_register, period_l_register};
                    end
                    else begin
                        // Stop in one-shot mode
                        status_running <= 1'b0;
                        // Counter stays at 0
                    end
                end
                else begin
                    // Decrement
                    internal_counter <= internal_counter - 32'd1;
                end
            end

            // --------------------------------------------------------------
            // 5. Snapshot Functionality
            // --------------------------------------------------------------
            // Capture current counter value continuously or on specific trigger?
            // Specification says: "Allows capturing the current counter value for readback"
            // Usually implemented as a register that holds the value at the time of read request 
            // or updates continuously. For precise monitoring without metastability during read,
            // we update it every cycle or latch it. Let's update every cycle for "live" snapshot.
            snapshot_register <= internal_counter;

        end
    end

    // ------------------------------------------------------------------------
    // Output Logic: IRQ
    // ------------------------------------------------------------------------
    // Interrupt is asserted if timeout occurred AND interrupts are enabled
    assign irq = status_timeout && ctrl_int_enable;

    // ------------------------------------------------------------------------
    // Output Logic: Read Data Multiplexer
    // ------------------------------------------------------------------------
    reg [31:0] readdata_reg;

    always @(*) begin
        readdata_reg = 32'd0; // Default
        
        if (chipselect && write_n) begin // Read cycle
            case (address)
                ADDR_SNAP_L: 
                    readdata_reg = {16'd0, snapshot_register[15:0]};
                
                ADDR_SNAP_H: 
                    readdata_reg = {16'd0, snapshot_register[31:16]};
                
                ADDR_STATUS: begin
                    readdata_reg[0] = status_timeout;
                    readdata_reg[1] = status_running;
                    readdata_reg[2] = ctrl_int_enable; // Readback control bits often mirrored
                    readdata_reg[3] = ctrl_cont_mode;
                    readdata_reg[31:4] = 32'd0;
                end
                
                ADDR_COUNT_L:
                    readdata_reg = {16'd0, internal_counter[15:0]};
                
                ADDR_COUNT_H:
                    readdata_reg = {16'd0, internal_counter[31:16]};
                    
                // Fallback for period reads if mapped differently, 
                // but spec implies snapshot for readback. 
                // If software reads period registers directly:
                ADDR_PERIOD_L:
                    readdata_reg = {16'd0, period_l_register};
                ADDR_PERIOD_H:
                    readdata_reg = {16'd0, period_h_register};
                    
                default:
                    readdata_reg = 32'd0;
            endcase
        end
    end

    assign readdata = readdata_reg;

endmodule
