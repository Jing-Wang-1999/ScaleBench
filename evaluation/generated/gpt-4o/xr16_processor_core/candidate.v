module xr16_processor_core(
    input wire clk,
    input wire rst,
    input wire rdy,
    input wire ud_t,
    input wire ld_t,
    input wire udlt_t,
    input wire int_req,
    input wire dma_req,
    input wire zerodma,
    input wire [15:0] insn,
    output reg mem_ce,
    output reg word_nxt,
    output reg read_nxt,
    output reg dbus_nxt,
    output reg dma,
    output reg [15:0] addr_nxt,
    inout wire [15:0] d
);

    // Internal registers for control signals
    reg mem_ce_reg;
    reg word_nxt_reg;
    reg read_nxt_reg;
    reg dbus_nxt_reg;
    reg dma_reg;
    reg [15:0] d_reg;

    // Sequential logic for control path
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Clear all control registers on reset
            mem_ce_reg <= 0;
            word_nxt_reg <= 0;
            read_nxt_reg <= 0;
            dbus_nxt_reg <= 0;
            dma_reg <= 0;
        end else if (rdy) begin
            // Update control registers based on instruction bits and dma_req
            mem_ce_reg <= insn[0];
            word_nxt_reg <= insn[1];
            read_nxt_reg <= insn[2];
            dbus_nxt_reg <= insn[3];
            dma_reg <= dma_req;
        end
    end

    // Sequential logic for data path
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Clear addr_nxt and d registers on reset
            addr_nxt <= 16'b0;
            d_reg <= 16'b0; // Dummy value
        end else if (rdy) begin
            // Update addr_nxt based on instruction bits
            addr_nxt <= insn[15:0];
            d_reg <= 16'b0; // Reset d to a dummy value
        end
    end

    // Connect internal registers to output ports
    assign mem_ce = mem_ce_reg;
    assign word_nxt = word_nxt_reg;
    assign read_nxt = read_nxt_reg;
    assign dbus_nxt = dbus_nxt_reg;
    assign dma = dma_reg;
    assign d = (rdy) ? d_reg : 16'bz; // Tri-state buffer for d

endmodule
