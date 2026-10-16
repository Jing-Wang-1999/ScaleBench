module clocked_signed_magnitude_calculator(
    input Clock,
    input [10:0] binaryOperand1,
    input [10:0] binaryOperand2,
    input [3:0] operator,
    output reg [20:0] answer,
    output reg sign
);

    wire [10:0] normieOperand1;
    wire [10:0] normieOperand2;

    // Calculate two's complement (negation) of the operands
    assign normieOperand1 = ~binaryOperand1 + 1'b1;
    assign normieOperand2 = ~binaryOperand2 + 1'b1;

    always @(posedge Clock) begin
        case (operator)
            4'b1101: begin // Multiplication
                sign = binaryOperand1[10] ^ binaryOperand2[10];
                if (binaryOperand1[10] == 1'b0 && binaryOperand2[10] == 1'b0) begin
                    answer = binaryOperand1 * binaryOperand2;
                end else if (binaryOperand1[10] == 1'b1 && binaryOperand2[10] == 1'b0) begin
                    answer = normieOperand1 * binaryOperand2;
                end else if (binaryOperand1[10] == 1'b0 && binaryOperand2[10] == 1'b1) begin
                    answer = binaryOperand1 * normieOperand2;
                end else begin
                    answer = normieOperand1 * normieOperand2;
                end
            end

            4'b1110: begin // Subtraction
                answer = binaryOperand1 - binaryOperand2;
                if (answer[20] == 1'b1) begin
                    sign = 1'b1;
                    answer = ~answer + 1'b1;
                end else begin
                    sign = 1'b0;
                end
            end

            4'b1111: begin // Addition
                answer = binaryOperand1 + binaryOperand2;
                if (answer[20] == 1'b1) begin
                    sign = 1'b1;
                    answer = ~answer + 1'b1;
                end else begin
                    sign = 1'b0;
                end
            end

            default: begin
                answer = 21'b0;
                sign = 1'b0;
            end
        endcase
    end

endmodule
