module z80_dual_psg_audio_controller
(
   input         clock,
   input         reset,
   input         ena,
   
   input         phi_n,
   input         phi_en,
   input  [15:0] addr,
   input   [7:0] din,
   output  [7:0] dout,
   input   [7:0] cpu_di,		
   input         m1_n,
   input         iorq_n,
   input         rd_n,
   input         wr_n,
   output        int_n,
   output        nmi,
   
   input         cursor,
   
   output  [7:0] audio_l,
   output  [7:0] audio_r
);

   // Internal signals
   reg [7:0] ctc_dout;
   reg [7:0] ay_dout;
   reg soft_reset;
   reg ctc_ce_n;
   reg ay_sel;
   reg [7:0] chl_a, chl_b, chl_c;
   reg [7:0] chr_a, chr_b, chr_c;
   reg [7:0] reg_a, reg_b, reg_c;
   reg int_n_reg;
   reg nmi_reg;

   // Soft reset logic
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         soft_reset <= 1'b0;
      end else begin
         soft_reset <= ena && !iorq_n && !m1_n && (addr == 16'hF8FF);
      end
   end

   // CTC clock enable logic
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         ctc_ce_n <= 1'b1;
      end else begin
         ctc_ce_n <= phi_en;
      end
   end

   // AY-3-8910 chip selection logic
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         ay_sel <= 1'b0;
      end else begin
         ay_sel <= (addr[15:8] == 8'hF8);
      end
   end

   // Interrupt and NMI logic
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         int_n_reg <= 1'b1;
         nmi_reg <= 1'b1;
      end else begin
         int_n_reg <= !soft_reset;
         nmi_reg <= !soft_reset;
      end
   end

   // Data output logic
   assign dout = (ay_sel) ? ay_dout : ctc_dout;

   // Audio signal generation
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         chl_a <= 8'b0;
         chl_b <= 8'b0;
         chl_c <= 8'b0;
         chr_a <= 8'b0;
         chr_b <= 8'b0;
         chr_c <= 8'b0;
      end else begin
         // Assuming reg_a, reg_b, reg_c are updated by YM2149 instances
         chl_a <= reg_a;
         chl_b <= reg_b;
         chl_c <= reg_c;
         chr_a <= reg_a;
         chr_b <= reg_b;
         chr_c <= reg_c;
      end
   end

   assign audio_l = chl_a + chl_b + chl_c;
   assign audio_r = chr_a + chr_b + chr_c;

   // Output assignments
   assign int_n = int_n_reg;
   assign nmi = nmi_reg;

endmodule
