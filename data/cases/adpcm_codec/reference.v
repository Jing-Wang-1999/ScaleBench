module adpcm_codec                      
  (
    input clk,                     
    input reset,                   
    input signed [15:0] x_in,      
    output [3:0] y_out,           
    output signed [15:0] p_out,  
    output reg p_underflow, p_overflow, 
    output signed [7:0] i_out,         
    output reg i_underflow, i_overflow, 
    output signed [15:0] err,          
    output [14:0] sz_out,               
    output s_out
  );

  reg signed [15:0] va, va_d; 
  reg sign; 
  reg [3:0] sdelta; 
  reg [14:0] step; 
  reg signed [15:0] valpred; 
  reg signed [7:0] index; 
  reg signed [16:0] diff0, diff1, diff2, diff3;   
  reg signed [16:0] p1, p2, p3;      
  reg signed [7:0] i1, i2, i3;      
  reg [3:0] delta2, delta3, delta4;  
  reg [14:0] tStep;
  reg signed [15:0] vpdiff2, vpdiff3, vpdiff4;  

  wire signed [4:0] indexTable [0:15] = {-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8};

  wire [14:0] t [0:88] = {
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 
    130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 
    408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166,
    1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 
    3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 
    8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 
    20350, 22385, 24623, 27086, 29794, 32767
  };

  always @(posedge clk or posedge reset) begin : Encode
    if (reset) begin  
      va <= 0; 
      va_d <= 0;
      step <= 0; 
      index <= 0;
      valpred <= 0;
    end else begin 
      va_d <= va;      
      va <= x_in;
      step <= t[i3];
      index <= i3;
      valpred <= p3;         
    end
  end
  
  always @(va, va_d, step, index, valpred) begin
    diff0 = va - valpred;
    if (diff0 < 0) begin
      sign = 1;      
      diff1 = -diff0;
    end else begin
      sign = 0;
      diff1 = diff0;
    end

    if (diff1 >= step) begin  
      delta2 = 4; 
      diff2 = diff1 - step; 
      vpdiff2 = step / 8 + step;
    end else begin
      delta2 = 0; 
      diff2 = diff1; 
      vpdiff2 = step / 8;
    end
    if (diff2 >= step / 2) begin 
      delta3 = delta2 + 2; 
      diff3 = diff2 - step / 2; 
      vpdiff3 = vpdiff2 + step / 2;
    end else begin
      delta3 = delta2; 
      diff3 = diff2; 
      vpdiff3 = vpdiff2;
    end
    if (diff3 >= step / 4) begin
      delta4 = delta3 + 1; 
      vpdiff4 = vpdiff3 + step / 4;
    end else begin
      delta4 = delta3; 
      vpdiff4 = vpdiff3;
    end
  
    if (sign) p1 = valpred - vpdiff4;
    else p1 = valpred + vpdiff4;
  
    if (p1 > 32767) begin  
      p2 = 32767; 
      p_overflow = 1;
    end else begin
      p2 = p1; 
      p_overflow = 0;    
    end
    if (p2 < -32768) begin  
      p3 = -32768; 
      p_underflow = 1; 
    end else begin
      p3 = p2; 
      p_underflow = 0; 
    end

    i1 = index + indexTable[delta4];
    if (i1 < 0) begin      
      i2 = 0; 
      i_underflow = 1;
    end else begin
      i2 = i1; 
      i_underflow = 0;
    end
    if (i2 > 88) begin
      i3 = 88; 
      i_overflow = 1;
    end else begin
      i3 = i2; 
      i_overflow = 0;
    end
    if (sign) sdelta = delta4 + 8;
    else sdelta = delta4;
  end
   
  assign y_out = sdelta;    
  assign p_out = valpred;
  assign i_out = index;
  assign sz_out = step;
  assign s_out = sign;
  assign err = va_d - valpred;
   
endmodule