module clocked_signed_magnitude_calculator(
    input Clock,
    input [10:0] binaryOperand1,
    input [10:0] binaryOperand2,
    input [3:0] operator,
    output reg [20:0] answer,
    output reg sign
);

    // Two's complement versions of operands
    wire [10:0] normieOperand1;
    wire [10:0] normieOperand2;
    
    // Continuous assignments for two's complement
    assign normieOperand1 = ~binaryOperand1 + 1'b1;
    assign normieOperand2 = ~binaryOperand2 + 1'b1;
    
    // Intermediate signals for arithmetic operations
    reg [20:0] temp_result;
    reg temp_sign;
    
    always @(posedge Clock) begin
        case (operator)
            // Multiplication: 4'b1101
            4'b1101: begin
                // Determine sign by XORing sign bits
                sign <= binaryOperand1[10] ^ binaryOperand2[10];
                
                // Perform signed multiplication based on sign bits
                if (binaryOperand1[10] == 0 && binaryOperand2[10] == 0) begin
                    // Both positive: multiply directly
                    answer <= {10'b0, binaryOperand1[9:0]} * {10'b0, binaryOperand2[9:0]};
                end
                else if (binaryOperand1[10] == 1 && binaryOperand2[10] == -0) begin
                    // Operand1 negative, Operand2 positive: multiply absolute values
                    answer <= {10'b0, normieOperand1[9:0]} * {10'b0, binaryOperand2[9:0]};
                end
                else if (binaryOperand1[10] == 0 && binaryOperand2[10] == 1) begin
                    // Operand1 positive, Operand2 negative: multiply absolute values
                    answer <= {10'b0, binaryOperand1[9:0]} * {10'b0, normieOperand2[9:0]};
                end
                else begin
                    // Both negative: multiply absolute values
                    answer <= {10'b0, normieOperand1[9:0]} * {10'b0, normieOperand2[9:0]};
                end
            end
            
            // Subtraction: 4'b1110
            4'b1110: begin
                // Perform subtraction
                temp_result = {11'b0, binaryOperand1} - {11'b0, binaryOperand2};
                
                // Check if result is negative
                if (temp_result[20]) begin
                    // Result is negative: set sign and convert to positive
                    sign <= 1'b1;
                    answer <= ~temp_result + 1'b1;
                end
                else begin
                    // Result is positive or zero
                    sign <= 1'b0;
                    answer <= temp_result;
                end
            end
            
            // Addition: 4'b1111
            4'b1111: begin
                // Perform addition
                temp_result = {11'b0, binaryOperand1} + {11'b0, binaryOperand2};
                
                // Check if result is negative
                if (temp_result[20]) begin
                    // Result is negative: set sign and convert to positive
                    sign <= 1'b1;
                    answer <= ~temp_result + 1'b1;
                end
                else begin
                    // Result is positive or zero
                    sign <= 1'b0;
                    answer <= temp_result;
                end
            end
            
            // Default case: maintain current values
            default: begin
                answer <= answer;
                sign <= sign;
            end
        endcase
    end

endmodule
