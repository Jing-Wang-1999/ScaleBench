module dma_tdsp_bus_arbiter (
    input reset,
    input clk,
    input dma_breq,
    output reg dma_grant,
    input tdsp_breq,
    output reg tdsp_grant
);

    localparam IDLE = 3'b000;
    localparam GRANT_TDSP = 3'b001;
    localparam GRANT_DMA = 3'b010;
    localparam DMA_PRI = 3'b011;
    localparam CLEAR = 3'b100;

    reg [2:0] state;

    // State Transition Logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (tdsp_breq)
                        state <= GRANT_TDSP;
                    else if (dma_breq)
                        state <= GRANT_DMA;
                    else
                        state <= IDLE;
                end
                GRANT_TDSP: begin
                    if (tdsp_breq)
                        state <= GRANT_TDSP;
                    else
                        state <= CLEAR;
                end
                GRANT_DMA: begin
                    if (dma_breq)
                        state <= GRANT_DMA;
                    else
                        state <= CLEAR;
                end
                DMA_PRI: begin
                    if (!tdsp_breq)
                        state <= GRANT_DMA;
                    else
                        state <= GRANT_TDSP;
                end
                CLEAR: begin
                    if (tdsp_breq)
                        state <= GRANT_TDSP;
                    else if (dma_breq)
                        state <= DMA_PRI;
                    else
                        state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    // Output Control Logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dma_grant = 0;
            tdsp_grant = 0;
        end else begin
            case (state)
                IDLE: begin
                    dma_grant = 0;
                    tdsp_grant = 0;
                end
                GRANT_TDSP: begin
                    dma_grant = 0;
                    tdsp_grant = 1;
                end
                GRANT_DMA: begin
                    dma_grant = 1;
                    tdsp_grant = 0;
                end
                DMA_PRI: begin
                    dma_grant = 1;
                    tdsp_grant = 0;
                end
                CLEAR: begin
                    dma_grant = 0;
                    tdsp_grant = 1;
                end
                default: begin
                    dma_grant = 0;
                    tdsp_grant = 0;
                end
            endcase
        end
    end

endmodule
