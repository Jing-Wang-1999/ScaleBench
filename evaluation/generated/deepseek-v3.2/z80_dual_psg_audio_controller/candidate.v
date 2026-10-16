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
   wire        soft_reset;
   wire        ctc_ce_n;
   wire        ay_sel;
   wire        ctc_int_n;
   wire        ctc_nmi;
   wire  [7:0] ctc_dout;
   wire        ctc_trg0;
   wire        ctc_trg1;
   wire        ctc_trg2;
   wire        ctc_trg3;
   
   wire  [7:0] ay_left_dout;
   wire  [7:0] ay_right_dout;
   wire  [7:0] chl_a, chl_b, chl_c;
   wire  [7:0] chr_a, chr_b, chr_c;
   
   reg   [7:0] audio_l_reg;
   reg   [7:0] audio_r_reg;
   
   // Soft reset generation
   assign soft_reset = ena && !iorq_n && !m1_n && (addr == 16'hF8FF);
   
   // CTC chip enable
   assign ctc_ce_n = !(ena && !iorq_n && (addr[7:0] == 8'hF8));
   
   // AY chip select
   assign ay_sel = ena && !iorq_n && (addr[7:0] == 8'hF9);
   
   // Instantiate Z80 CTC
   z80_ctc ctc_inst (
      .clock(clock),
      .reset(reset || soft_reset),
      .ce_n(ctc_ce_n),
      .cs0(addr[0]),
      .cs1(addr[1]),
      .m1_n(m1_n),
      .iorq_n(iorq_n),
      .rd_n(rd_n),
      .din(din),
      .dout(ctc_dout),
      .int_n(ctc_int_n),
      .nmi(ctc_nmi),
      .trg0(ctc_trg0),
      .trg1(ctc_trg1),
      .trg2(ctc_trg2),
      .trg3(ctc_trg3),
      .clk_trg0(phi_n),
      .clk_trg1(phi_n),
      .clk_trg2(phi_n),
      .clk_trg3(phi_n)
   );
   
   // Instantiate left YM2149 (AY-3-8910)
   ym2149 ay_left (
      .clock(clock),
      .reset(reset || soft_reset),
      .ena(ena),
      .sel(ay_sel && !addr[8]),
      .bdir(!wr_n && ay_sel && !addr[8]),
      .bc1(!rd_n && ay_sel && !addr[8]),
      .din(din),
      .dout(ay_left_dout),
      .ch_a(chl_a),
      .ch_b(chl_b),
      .ch_c(chl_c)
   );
   
   // Instantiate right YM2149 (AY-3-8910)
   ym2149 ay_right (
      .clock(clock),
      .reset(reset || soft_reset),
      .ena(ena),
      .sel(ay_sel && addr[8]),
      .bdir(!wr_n && ay_sel && addr[8]),
      .bc1(!rd_n && ay_sel && addr[8]),
      .din(din),
      .dout(ay_right_dout),
      .ch_a(chr_a),
      .ch_b(chr_b),
      .ch_c(chr_c)
   );
   
   // Output multiplexing
   assign dout = (!ctc_ce_n && !rd_n) ? ctc_dout :
                 (!rd_n && ay_sel && !addr[8]) ? ay_left_dout :
                 (!rd_n && ay_sel && addr[8]) ? ay_right_dout :
                 8'h00;
   
   assign int_n = ctc_int_n;
   assign nmi = ctc_nmi;
   
   // Audio mixing
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         audio_l_reg <= 8'h00;
         audio_r_reg <= 8'h00;
      end else if (ena) begin
         // Sum channels with saturation
         audio_l_reg <= chl_a + chl_b + chl_c;
         audio_r_reg <= chr_a + chr_b + chr_c;
      end
   end
   
   assign audio_l = audio_l_reg;
   assign audio_r = audio_r_reg;

endmodule

// Z80 CTC module
module z80_ctc
(
   input        clock,
   input        reset,
   input        ce_n,
   input        cs0,
   input        cs1,
   input        m1_n,
   input        iorq_n,
   input        rd_n,
   input  [7:0] din,
   output [7:0] dout,
   output       int_n,
   output       nmi,
   output       trg0,
   output       trg1,
   output       trg2,
   output       trg3,
   input        clk_trg0,
   input        clk_trg1,
   input        clk_trg2,
   input        clk_trg3
);

   // Internal registers
   reg [7:0] counter0, counter1, counter2, counter3;
   reg [7:0] time_const0, time_const1, time_const2, time_const3;
   reg [2:0] mode0, mode1, mode2, mode3;
   reg       int_en0, int_en1, int_en2, int_en3;
   reg       retrigger0, retrigger1, retrigger2, retrigger3;
   reg       clk_edge0, clk_edge1, clk_edge2, clk_edge3;
   reg       prescaler0, prescaler1, prescaler2, prescaler3;
   
   reg [7:0] dout_reg;
   reg       int_n_reg;
   reg       nmi_reg;
   reg       trg0_reg, trg1_reg, trg2_reg, trg3_reg;
   
   reg [7:0] downcounter0, downcounter1, downcounter2, downcounter3;
   reg       active0, active1, active2, active3;
   
   // Channel selection
   wire [1:0] channel_sel = {cs1, cs0};
   
   // Write decoding
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         counter0 <= 8'h00;
         counter1 <= 8'h00;
         counter2 <= 8'h00;
         counter3 <= 8'h00;
         time_const0 <= 8'h00;
         time_const1 <= 8'h00;
         time_const2 <= 8'h00;
         time_const3 <= 8'h00;
         mode0 <= 3'b000;
         mode1 <= 3'b000;
         mode2 <= 3'b000;
         mode3 <= 3'b000;
         int_en0 <= 1'b0;
         int_en1 <= 1'b0;
         int_en2 <= 1'b0;
         int_en3 <= 1'b0;
         retrigger0 <= 1'b0;
         retrigger1 <= 1'b0;
         retrigger2 <= 1'b0;
         retrigger3 <= 1'b0;
         clk_edge0 <= 1'b0;
         clk_edge1 <= 1'b0;
         clk_edge2 <= 1'b0;
         clk_edge3 <= 1'b0;
         prescaler0 <= 1'b0;
         prescaler1 <= 1'b0;
         prescaler2 <= 1'b0;
         prescaler3 <= 1'b0;
         active0 <= 1'b0;
         active1 <= 1'b0;
         active2 <= 1'b0;
         active3 <= 1'b0;
         downcounter0 <= 8'h00;
         downcounter1 <= 8'h00;
         downcounter2 <= 8'h00;
         downcounter3 <= 8'h00;
      end else if (!ce_n && !iorq_n && !wr_n) begin
         case (channel_sel)
            2'b00: begin // Channel 0
               if (din[0]) begin // Control word
                  mode0 <= din[7:5];
                  int_en0 <= din[6];
                  retrigger0 <= din[4];
                  clk_edge0 <= din[3];
                  prescaler0 <= din[2];
                  if (din[1]) begin // Time constant follows
                     time_const0 <= din;
                     downcounter0 <= din;
                     active0 <= 1'b1;
                  end
               end else begin // Time constant
                  time_const0 <= din;
                  downcounter0 <= din;
                  active0 <= 1'b1;
               end
            end
            2'b01: begin // Channel 1
               if (din[0]) begin // Control word
                  mode1 <= din[7:5];
                  int_en1 <= din[6];
                  retrigger1 <= din[4];
                  clk_edge1 <= din[3];
                  prescaler1 <= din[2];
                  if (din[1]) begin // Time constant follows
                     time_const1 <= din;
                     downcounter1 <= din;
                     active1 <= 1'b1;
                  end
               end else begin // Time constant
                  time_const1 <= din;
                  downcounter1 <= din;
                  active1 <= 1'b1;
               end
            end
            2'b10: begin // Channel 2
               if (din[0]) begin // Control word
                  mode2 <= din[7:5];
                  int_en2 <= din[6];
                  retrigger2 <= din[4];
                  clk_edge2 <= din[3];
                  prescaler2 <= din[2];
                  if (din[1]) begin // Time constant follows
                     time_const2 <= din;
                     downcounter2 <= din;
                     active2 <= 1'b1;
                  end
               end else begin // Time constant
                  time_const2 <= din;
                  downcounter2 <= din;
                  active2 <= 1'b1;
               end
            end
            2'b11: begin // Channel 3
               if (din[0]) begin // Control word
                  mode3 <= din[7:5];
                  int_en3 <= din[6];
                  retrigger3 <= din[4];
                  clk_edge3 <= din[3];
                  prescaler3 <= din[2];
                  if (din[1]) begin // Time constant follows
                     time_const3 <= din;
                     downcounter3 <= din;
                     active3 <= 1'b1;
                  end
               end else begin // Time constant
                  time_const3 <= din;
                  downcounter3 <= din;
                  active3 <= 1'b1;
               end
            end
         endcase
      end
   end
   
   // Counter logic
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         trg0_reg <= 1'b0;
         trg1_reg <= 1'b0;
         trg2_reg <= 1'b0;
         trg3_reg <= 1'b0;
         int_n_reg <= 1'b1;
         nmi_reg <= 1'b0;
      end else begin
         // Channel 0
         if (active0) begin
            if (downcounter0 == 8'h00) begin
               trg0_reg <= 1'b1;
               if (int_en0) int_n_reg <= 1'b0;
               nmi_reg <= 1'b1;
               downcounter0 <= time_const0;
            end else begin
               downcounter0 <= downcounter0 - 1;
               trg0_reg <= 1'b0;
               nmi_reg <= 1'b0;
            end
         end
         
         // Channel 1
         if (active1) begin
            if (downcounter1 == 8'h00) begin
               trg1_reg <= 1'b1;
               if (int_en1) int_n_reg <= 1'b0;
               downcounter1 <= time_const1;
            end else begin
               downcounter1 <= downcounter1 - 1;
               trg1_reg <= 1'b0;
            end
         end
         
         // Channel 2
         if (active2) begin
            if (downcounter2 == 8'h00) begin
               trg2_reg <= 1'b1;
               if (int_en2) int_n_reg <= 1'b0;
               downcounter2 <= time_const2;
            end else begin
               downcounter2 <= downcounter2 - 1;
               trg2_reg <= 1'b0;
            end
         end
         
         // Channel 3
         if (active3) begin
            if (downcounter3 == 8'h00) begin
               trg3_reg <= 1'b1;
               if (int_en3) int_n_reg <= 1'b0;
               downcounter3 <= time_const3;
            end else begin
               downcounter3 <= downcounter3 - 1;
               trg3_reg <= 1'b0;
            end
         end
      end
   end
   
   // Read logic
   always @(*) begin
      case (channel_sel)
         2'b00: dout_reg = counter0;
         2'b01: dout_reg = counter1;
         2'b10: dout_reg = counter2;
         2'b11: dout_reg = counter3;
         default: dout_reg = 8'h00;
      endcase
   end
   
   assign dout = (!ce_n && !iorq_n && !rd_n) ? dout_reg : 8'h00;
   assign int_n = int_n_reg;
   assign nmi = nmi_reg;
   assign trg0 = trg0_reg;
   assign trg1 = trg1_reg;
   assign trg2 = trg2_reg;
   assign trg3 = trg3_reg;

endmodule

// YM2149 (AY-3-8910) module
module ym2149
(
   input        clock,
   input        reset,
   input        ena,
   input        sel,
   input        bdir,
   input        bc1,
   input  [7:0] din,
   output [7:0] dout,
   output [7:0] ch_a,
   output [7:0] ch_b,
   output [7:0] ch_c
);

   // Internal registers
   reg [7:0] regs[15:0];
   reg [3:0] addr_reg;
   reg [7:0] dout_reg;
   
   // Tone generators
   reg [11:0] tone_cnt_a, tone_cnt_b, tone_cnt_c;
   reg        tone_out_a, tone_out_b, tone_out_c;
   
   // Noise generator
   reg [16:0] noise_cnt;
   reg        noise_out;
   
   // Envelope generator
   reg [15:0] env_cnt;
   reg [3:0]  env_step;
   reg        env_hold, env_alt, env_attack, env_cont;
   reg [3:0]  env_volume;
   
   // Channel outputs
   reg [7:0] ch_a_reg, ch_b_reg, ch_c_reg;
   
   // Register write
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         addr_reg <= 4'h0;
         for (integer i = 0; i < 16; i = i + 1) begin
            regs[i] <= 8'h00;
         end
         tone_cnt_a <= 12'h000;
         tone_cnt_b <= 12'h000;
         tone_cnt_c <= 12'h000;
         noise_cnt <= 17'h00000;
         env_cnt <= 16'h0000;
         env_step <= 4'h0;
         env_hold <= 1'b0;
         env_alt <= 1'b0;
         env_attack <= 1'b0;
         env_cont <= 1'b0;
         env_volume <= 4'h0;
      end else if (ena && sel) begin
         if (bdir && !bc1) begin
            // Address write
            addr_reg <= din[3:0];
         end else if (bdir && bc1) begin
            // Data write
            regs[addr_reg] <= din;
            
            // Update envelope parameters
            if (addr_reg == 4'hD) begin
               env_hold <= din[3];
               env_alt <= din[2];
               env_attack <= din[1];
               env_cont <= din[0];
               env_step <= 4'h0;
            end
         end
      end
   end
   
   // Register read
   always @(*) begin
      case (addr_reg)
         4'h0: dout_reg = regs[0][7:0];
         4'h1: dout_reg = {4'h0, regs[1][3:0]};
         4'h2: dout_reg = regs[2][7:0];
         4'h3: dout_reg = {4'h0, regs[3][3:0]};
         4'h4: dout_reg = regs[4][7:0];
         4'h5: dout_reg = {4'h0, regs[5][3:0]};
         4'h6: dout_reg = regs[6][7:0];
         4'h7: dout_reg = {4'h0, regs[7][3:0]};
         4'h8: dout_reg = {regs[8][4:0], 3'b000};
         4'h9: dout_reg = {regs[9][4:0], 3'b000};
         4'hA: dout_reg = {regs[10][4:0], 3'b000};
         4'hB: dout_reg = regs[11][7:0];
         4'hC: dout_reg = regs[12][7:0];
         4'hD: dout_reg = {regs[13][7:4], 4'h0};
         4'hE: dout_reg = regs[14][7:0];
         4'hF: dout_reg = regs[15][7:0];
         default: dout_reg = 8'h00;
      endcase
   end
   
   // Tone generator logic
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         tone_out_a <= 1'b0;
         tone_out_b <= 1'b0;
         tone_out_c <= 1'b0;
      end else if (ena) begin
         // Channel A
         if (tone_cnt_a == 12'h000) begin
            tone_out_a <= ~tone_out_a;
            tone_cnt_a <= {regs[1][3:0], regs[0]};
         end else begin
            tone_cnt_a <= tone_cnt_a - 1;
         end
         
         // Channel B
         if (tone_cnt_b == 12'h000) begin
            tone_out_b <= ~tone_out_b;
            tone_cnt_b <= {regs[3][3:0], regs[2]};
         end else begin
            tone_cnt_b <= tone_cnt_b - 1;
         end
         
         // Channel C
         if (tone_cnt_c == 12'h000) begin
            tone_out_c <= ~tone_out_c;
            tone_cnt_c <= {regs[5][3:0], regs[4]};
         end else begin
            tone_cnt_c <= tone_cnt_c - 1;
         end
      end
   end
   
   // Noise generator logic
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         noise_out <= 1'b0;
         noise_cnt <= 17'h00000;
      end else if (ena) begin
         if (noise_cnt == 17'h00000) begin
            noise_out <= ~noise_out;
            noise_cnt <= {regs[6], 9'h000};
         end else begin
            noise_cnt <= noise_cnt - 1;
         end
      end
   end
   
   // Envelope generator logic
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         env_volume <= 4'h0;
         env_cnt <= 16'h0000;
      end else if (ena) begin
         if (env_cnt == 16'h0000) begin
            if (!env_hold) begin
               if (env_attack) begin
                  env_volume <= env_volume - 1;
               end else begin
                  env_volume <= env_volume + 1;
               end
               
               if (env_volume == 4'h0 || env_volume == 4'hF) begin
                  if (env_cont) begin
                     if (env_alt) env_attack <= ~env_attack;
                  end else begin
                     env_hold <= 1'b1;
                  end
               end
            end
            env_cnt <= {regs[12], regs[11]};
         end else begin
            env_cnt <= env_cnt - 1;
         end
      end
   end
   
   // Channel mixing
   always @(posedge clock or posedge reset) begin
      if (reset) begin
         ch_a_reg <= 8'h00;
         ch_b_reg <= 8'h00;
         ch_c_reg <= 8'h00;
      end else if (ena) begin
         // Channel A
         if ((tone_out_a || !regs[7][0]) && (noise_out || !regs[7][3])) begin
            if (regs[8][4]) begin
               ch_a_reg <= {env_volume, 4'h0};
            end else begin
               ch_a_reg <= {regs[8][3:0], 4'h0};
            end
         end else begin
            ch_a_reg <= 8'h00;
         end
         
         // Channel B
         if ((tone_out_b || !regs[7][1]) && (noise_out || !regs[7][4])) begin
            if (regs[9][4]) begin
               ch_b_reg <= {env_volume, 4'h0};
            end else begin
               ch_b_reg <= {regs[9][3:0], 4'h0};
            end
         end else begin
            ch_b_reg <= 8'h00;
         end
         
         // Channel C
         if ((tone_out_c || !regs[7][2]) && (noise_out || !regs[7][5])) begin
            if (regs[10][4]) begin
               ch_c_reg <= {env_volume, 4'h0};
            end else begin
               ch_c_reg <= {regs[10][3:0], 4'h0};
            end
         end else begin
            ch_c_reg <= 8'h00;
         end
      end
   end
   
   assign dout = (!sel && !bc1) ? dout_reg : 8'h00;
   assign ch_a = ch_a_reg;
   assign ch_b = ch_b_reg;
   assign ch_c = ch_c_reg;

endmodule
