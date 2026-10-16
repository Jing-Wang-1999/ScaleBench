module dma_tdsp_bus_arbiter (
    input wire reset,
    input wire clk,
    input wire dma_breq,
    output reg dma_grant,
    input wire tdsp_breq,
    output reg tdsp_grant
);

    // State encoding
    localparam IDLE       = 3'b000;
    localparam GRANT_TDSP = 3'b001;
    localparam GRANT_DMA  = 3'b010;
    localparam DMA_PRI    = 3'b011;
    localparam CLEAR      = 3'b100;

    reg [2:0] current_state, next_state;

    // State transition logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Next state logic
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (tdsp_breq)
                    next_state = GRANT_TDSP;
                else if (dma_breq)
                    next_state = GRANT_DMA;
                else
                    next_state = IDLE;
            end
            GRANT_TDSP: begin
                if (tdsp_breq)
                    next_state = GRANT_TDSP;
                else
                    next_state = CLEAR;
            end
            GRANT_DMA: begin
                if (dma_breq)
                    next_state = GRANT_DMA;
                else
                    next_state = CLEAR;
            end
            DMA_PRI: begin
                if (tdsp_breq)
                    next_state = GRANT_TDSP;
                else
                    next_state = GRANT_DMA;
            end
            CLEAR: begin
                if (tdsp_breq)
                    next_state = GRANT_TDSP;
                else if (dma_breq)
                    next_state = DMA_PRI;
                else
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // Output logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dma_grant <= 0;
            tdsp_grant <= 0;
        end else begin
            case (next_state)
                IDLE: begin
                    dma_grant <= 0;
                    tdsp_grant <= 0;
                end
                GRANT_TDSP: begin
                    dma_grant <= 0;
                    tdsp_grant <= 1;
                end
                GRANT_DMA: begin
                    dma_grant <= 1;
                    tdsp_grant <= 0;
                end
                DMA_PRI: begin
                    dma_grant <= 1;
                    tdsp_grant <= 0;
                end
                CLEAR: begin
                    dma_grant <= 0;
                    tdsp_grant <= 0;
                end
                default: begin
                    dma_grant <= 0;
                    tdsp_grant <= 0;
                end
            endcase
        end
    end

endmodule
