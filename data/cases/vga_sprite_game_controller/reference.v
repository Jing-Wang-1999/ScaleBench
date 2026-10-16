module vga_sprite_game_controller (
    input  clk,
    output vga_h_sync,
    output vga_v_sync,
    output vga_R,
    output vga_G,
    output vga_B,
    input  up,
    input  down,
    input  left,
    input  right,
    input  shoot,
    output test,
    input  reset
);

  reg [9:0] pixel_x;
  reg [9:0] pixel_y;

  reg [17:0] movement_divider;
  reg [9:0] character_x;
  reg [8:0] character_y;

  wire in_display_area;
  wire border_pixel;
  wire character_pixel;

  // Generate an 800-by-525 raster with a 640-by-480 visible area.
  always @(posedge clk) begin
    if (reset) begin
      pixel_x <= 10'd0;
      pixel_y <= 10'd0;
    end else if (pixel_x == 10'd799) begin
      pixel_x <= 10'd0;
      if (pixel_y == 10'd524)
        pixel_y <= 10'd0;
      else
        pixel_y <= pixel_y + 10'd1;
    end else begin
      pixel_x <= pixel_x + 10'd1;
    end
  end

  // Move the character by one pixel every 200,000 input-clock cycles. The
  // direction inputs are active low and use up/down/left/right priority.
  always @(posedge clk) begin
    if (reset) begin
      movement_divider <= 18'd0;
      character_x <= 10'd320;
      character_y <= 9'd240;
    end else if (movement_divider == 18'd199999) begin
      movement_divider <= 18'd0;

      if (!up && (character_y > 9'd0))
        character_y <= character_y - 9'd1;
      else if (!down && (character_y < 9'd472))
        character_y <= character_y + 9'd1;
      else if (!left && (character_x > 10'd0))
        character_x <= character_x - 10'd1;
      else if (!right && (character_x < 10'd632))
        character_x <= character_x + 10'd1;
    end else begin
      movement_divider <= movement_divider + 18'd1;
    end
  end

  assign in_display_area = (pixel_x < 10'd640) && (pixel_y < 10'd480);

  assign vga_h_sync = (pixel_x >= 10'd656) && (pixel_x < 10'd752);
  assign vga_v_sync = (pixel_y >= 10'd490) && (pixel_y < 10'd492);

  assign border_pixel = (pixel_x < 10'd8) ||
                        (pixel_x >= 10'd632 && pixel_x < 10'd640) ||
                        (pixel_y < 10'd8) ||
                        (pixel_y >= 10'd472 && pixel_y < 10'd480);

  assign character_pixel = (pixel_x >= character_x) &&
                           (pixel_x < character_x + 10'd8) &&
                           (pixel_y >= character_y) &&
                           (pixel_y < character_y + 9'd8);

  assign vga_R = in_display_area && (border_pixel || character_pixel);
  assign vga_G = in_display_area && (border_pixel || character_pixel);
  assign vga_B = in_display_area && (border_pixel || character_pixel);

  // Bullet and enemy logic is outside this reduced sprite controller.
  assign test = 1'b0;

endmodule
