module dma_tdsp_bus_arbiter (
    input reset,
    input clk,
    input dma_breq,
    output reg dma_grant,
    input tdsp_breq,
    output reg tdsp_grant
);

    // State encoding
    localparam [2:0] IDLE      = 3'b000;
    localparam [2:0] GRANT_TDSP = 3'b001;
    localparam [2:0] GRANT_DMA  = 3'b010;
    localparam [2:0] DMA_PRI    = 3'b011;
    localparam [2:0] CLEAR      = 3'b100;

    // State register
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
                if (tdsp_breq) begin
                    next_state = GRANT_TDSP;
                end else if (dma_breq) begin
                    next_state = GRANT_DMA;
                end else begin
                    next_state = IDLE;
                end
            end

            GRANT_TDSP: begin
                if (tdsp_breq) begin
                    next_state = GRANT_TDSP;
                end else begin
                    next_state = CLEAR;
                end
            end

            GRANT_DMA: begin
                if (dma_breq) begin
                    next_state = GRANT_DMA;
                end else begin
                    next_state = CLEAR;
                end
            end

            DMA_PRI: begin
                if (tdsp_breq) begin
                    next_state = GRANT_TDSP;
                end else if (dma_breq) begin
                    next_state = GRANT_DMA;
                end else begin
                    next_state = IDLE;
                end
            end

            CLEAR: begin
                if (tdsp_breq) begin
                    next_state = GRANT_TDSP;
                end else if (dma_breq) begin
                    next_state = DMA_PRI;
                end else begin
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // Output logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dma_grant = 1'b0;
            tdsp_grant = 1'b0;
        end else begin
            case (next_state)
                IDLE: begin
                    dma_grant = 1'b0;
                    tdsp_grant = 1'b0;
                end

                GRANT_TDSP: begin
                    dma_grant = 1'b0;
                    tdsp_grant = 1'b1;
                end

                GRANT_DMA: begin
                    dma_grant = 1'b1;
                    tdsp_grant = 1'b0;
                end

                DMA_PRI: begin
                    dma_grant = 1'b0;
                    tdsp_grant = 1'b0;
                end

                CLEAR: begin
                    dma_grant = 1'b0;
                    tdsp_grant = 1'b1;
                end

                default: begin
                    dma_grant = 1'b0;
                    tdsp_grant = 1'b0;
                end
            endcase
        end
    end

endmodule
