module xr16_processor_core(
    input  wire        clk,
    input  wire        rst,
    input  wire        rdy,
    input  wire        ud_t,
    input  wire        ld_t,
    input  wire        udlt_t,
    input  wire        int_req,
    input  wire        dma_req,
    input  wire        zerodma,
    input  wire [15:0] insn,
    output reg         mem_ce,
    output reg         word_nxt,
    output reg         read_nxt,
    output reg         dbus_nxt,
    output reg         dma,
    output reg [15:0]  addr_nxt,
    inout  wire [15:0] d
);

    // Internal registers for control signals
    reg mem_ce_reg;
    reg word_nxt_reg;
    reg read_nxt_reg;
    reg dbus_nxt_reg;
    reg dma_reg;
    
    // Internal register for data bus direction/value (tri-state control logic)
    reg [15:0] d_reg;
    reg d_oe; // Output enable for d

    // Mapping instruction bits to control signals based on specification
    // Assumption: Specific bits of insn map directly to control outputs as per "instruction bits are directly taken"
    // We map lower bits of insn to the single bit control signals for demonstration of direct propagation
    // Bit 0 -> mem_ce, Bit 1 -> word_nxt, Bit 2 -> read_nxt, Bit 3 -> dbus_nxt, Bit 4 -> dma
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_ce_reg    <= 1'b0;
            word_nxt_reg  <= 1'b0;
            read_nxt_reg  <= 1'b0;
            dbus_nxt_reg  <= 1'b0;
            dma_reg       <= 1'b0;
        end
        else if (rdy) begin
            // Update control registers based on specific bits of the instruction
            // and dma_req influence if necessary. The spec says "based on ... insn bits"
            // and mentions dma_req in the input list.
            
            mem_ce_reg    <= insn[0];
            word_nxt_reg  <= insn[1];
            read_nxt_reg  <= insn[2];
            dbus_nxt_reg  <= insn[3];
            
            // DMA logic: Spec says updated based on insn bits and dma_req
            // If dma_req is active, it might override or combine with insn. 
            // Following strict "bits directly taken" but acknowledging dma_req input:
            dma_reg       <= insn[4] | dma_req; 
        end
        // Else hold state (implicit in non-blocking assignments without else in this context if rdy is low, 
        // but explicitly holding is safer for synthesis if rdy acts as an enable)
        else begin
            mem_ce_reg    <= mem_ce_reg;
            word_nxt_reg  <= word_nxt_reg;
            read_nxt_reg  <= read_nxt_reg;
            dbus_nxt_reg  <= dbus_nxt_reg;
            dma_reg       <= dma_reg;
        end
    end

    // Data path logic for addr_nxt and d
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            addr_nxt <= 16'd0;
            d_reg    <= 16'd0; // Dummy value on reset
            d_oe     <= 1'b0;
        end
        else if (rdy) begin
            // addr_nxt receives the address from the instruction
            // Assuming upper bits or specific field of insn is the address. 
            // Using full insn for address as no specific split was defined, 
            // or typically addr is a subset. Let's assume insn contains the address directly.
            addr_nxt <= insn; 
            
            // d register is reset to a dummy value when the system is ready
            // Spec: "reset the d register to a dummy value" when rdy is high.
            // Using 16'hDEAD as a distinct dummy value.
            d_reg    <= 16'hDEAD;
            
            // Control output enable based on dbus_nxt logic or specific instruction bit
            // If dbus_nxt implies driving the bus, we enable output.
            if (insn[3]) 
                d_oe <= 1'b1;
            else
                d_oe <= 1'b0;
        end
        else begin
            // Hold values
            addr_nxt <= addr_nxt;
            d_reg    <= d_reg;
            d_oe     <= d_oe;
        end
    end

    // Assign internal registers to outputs
    assign mem_ce    = mem_ce_reg;
    assign word_nxt  = word_nxt_reg;
    assign read_nxt  = read_nxt_reg;
    assign dbus_nxt  = dbus_nxt_reg;
    assign dma       = dma_reg;
    
    // Tri-state buffer for bidirectional 'd'
    assign d = (d_oe) ? d_reg : 16'bz;

endmodule
