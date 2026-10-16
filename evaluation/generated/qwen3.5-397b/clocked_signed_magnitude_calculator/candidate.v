module clocked_signed_magnitude_calculator(
    input Clock,
    input [10:0] binaryOperand1,
    input [10:0] binaryOperand2,
    input [3:0] operator,
    output reg [20:0] answer,
    output reg sign
);

    // Intermediate wires for two's complement negation of inputs
    wire [10:0] normieOperand1;
    wire [10:0] normieOperand2;

    // Calculate two's complement: invert bits and add 1
    assign normieOperand1 = ~binaryOperand1 + 1'b1;
    assign normieOperand2 = ~binaryOperand2 + 1'b1;

    always @(posedge Clock) begin
        if (operator == 4'b1101) begin
            // Multiplication: 4'b1101
            // Determine sign by XORing the sign bits (MSB) of the two operands
            sign <= binaryOperand1[10] ^ binaryOperand2[10];
            
            // Perform multiplication based on sign scenarios
            // We treat the magnitude parts appropriately. 
            // If operand is negative, we use its positive magnitude (normie) for multiplication.
            // If operand is positive, we use the lower 10 bits as magnitude? 
            // Actually, standard signed magnitude logic:
            // If MSB is 0, value is positive, magnitude is [9:0] (or whole thing if interpreted as unsigned magnitude).
            // If MSB is 1, value is negative, magnitude is two's complement of the whole.
            // However, the prompt implies using the full 11-bit representation logic.
            // Let's follow the prompt's implication: "Execute signed multiplication considering different scenarios".
            // Usually in Signed Magnitude: Result Sign = S1 ^ S2. Result Mag = Mag1 * Mag2.
            // Magnitude of a positive number (MSB=0) in 11-bit SM is just the lower 10 bits? Or is the input format Two's Complement?
            // The prompt says "signed 11-bit binary inputs" but then asks for "sign indicator" and "convert to positive by taking two's complement" for add/sub.
            // This suggests the inputs might be treated as Two's Complement internally for calculation, but the output is forced into a Sign-Magnitude-like representation (Sign bit + Positive Magnitude in 'answer').
            // BUT, for multiplication, it explicitly says "Determine sign by XORing...".
            // Let's assume the inputs are standard Two's Complement numbers.
            // If Input is Two's Complement:
            // To get magnitude: if negative, take two's complement. If positive, keep as is.
            // Then multiply magnitudes.
            
            reg [10:0] mag1, mag2;
            reg [20:0] temp_prod;
            
            if (binaryOperand1[10]) 
                mag1 = normieOperand1;
            else 
                mag1 = binaryOperand1; // Keep positive as is (though bit 10 is 0, so it fits)
                
            if (binaryOperand2[10]) 
                mag2 = normieOperand2;
            else 
                mag2 = binaryOperand2;

            // Multiply magnitudes (11-bit * 11-bit -> 22-bit max, but we need 21-bit result)
            // Since max magnitude is 2^10 (if 11-bit signed), product is 2^20. Fits in 21 bits.
            temp_prod = mag1 * mag2;
            
            answer <= temp_prod[20:0];
            // Sign was already calculated via XOR above.
            // Note: If result is 0, sign doesn't strictly matter, but we keep the XOR result.
        end
        else if (operator == 4'b1110) begin
            // Subtraction: 4'b1110
            // Subtract binaryOperand2 from binaryOperand1
            // Inputs are treated as signed (Two's Complement likely, given the "negation" logic described)
            // Extend to 21 bits for calculation to handle overflow/sign correctly
            reg [20:0] diff;
            
            // Sign extend operands to 21 bits
            diff = {{10{binaryOperand1[10]}}, binaryOperand1} - {{10{binaryOperand2[10]}}, binaryOperand2};
            
            answer <= diff;
            
            // Check if result is negative (bit 20 is 1)
            if (diff[20]) begin
                sign <= 1'b1;
                // Convert to positive by taking two's complement
                answer <= ~diff + 1'b1;
            end
            else begin
                sign <= 1'b0;
                // answer is already assigned above, no change needed for positivity
            end
        end
        else if (operator == 4'b1111) begin
            // Addition: 4'b1111
            // Add binaryOperand1 and binaryOperand2
            reg [20:0] sum;
            
            // Sign extend operands to 21 bits
            sum = {{10{binaryOperand1[10]}}, binaryOperand1} + {{10{binaryOperand2[10]}}, binaryOperand2};
            
            answer <= sum;
            
            // Check if result is negative (bit 20 is 1)
            if (sum[20]) begin
                sign <= 1'b1;
                // Convert to positive by taking two's complement
                answer <= ~sum + 1'b1;
            end
            else begin
                sign <= 1'b0;
            end
        end
        else begin
            // Default case: hold values or reset? Specification doesn't define other ops.
            // Keeping previous values is standard for unspecified control codes in sequential logic unless reset exists.
            // No reset port provided.
        end
    end

endmodule
