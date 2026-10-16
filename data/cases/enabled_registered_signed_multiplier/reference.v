module enabled_registered_signed_multiplier (
    output reg  [63:0] Res,
    output wire        OVF,
    input       [31:0] A,
    input       [31:0] B,
    input              clk,
    input              reset,
    input              enable
);

  wire signed [31:0] signed_a;
  wire signed [31:0] signed_b;
  wire signed [63:0] full_product;

  assign signed_a = A;
  assign signed_b = B;
  assign full_product = signed_a * signed_b;

  always @(posedge clk or posedge reset) begin
    if (reset)
      Res <= 64'b0;
    else if (enable)
      Res <= full_product;
  end

  // Every signed 32-by-32-bit product is representable in 64 signed bits.
  assign OVF = 1'b0;

endmodule
