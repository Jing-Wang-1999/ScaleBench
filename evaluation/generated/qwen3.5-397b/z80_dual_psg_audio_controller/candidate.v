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

    // ------------------------------------------------------------------------
    // Internal Signals & Registers
    // ------------------------------------------------------------------------
    
    // Control Flags
    reg soft_reset;
    reg ctc_ce_n;
    reg ay_sel;
    
    // CTC Internal State
    reg [7:0] ctc_reg[3:0];       // 4 Channels (0-3)
    reg [7:0] ctc_control;        // Control word latch
    reg       ctc_int_enable;
    reg       ctc_int_pending;
    reg [3:0] ctc_channel_select; // Current channel being programmed
    
    // YM2149 Interface Signals
    wire [7:0] ym_left_data;
    wire [7:0] ym_right_data;
    wire       ym_bdir_left;
    wire       ym_bc1_left;
    wire       ym_bdir_right;
    wire       ym_bc1_right;
    
    // Audio Channel Outputs (Raw from PSGs)
    wire [7:0] chl_a, chl_b, chl_c; // Left channels
    wire [7:0] chr_a, chr_b, chr_c; // Right channels
    
    // Mixed Audio
    reg [9:0] audio_l_sum;
    reg [9:0] audio_r_sum;

    // ------------------------------------------------------------------------
    // Address Decoding & Control Logic
    // ------------------------------------------------------------------------

    // Decode Addresses
    // CTC Base Address assumed to be decoded via external logic or specific range.
    // Based on spec: Soft reset at 16'hF8FF when conditions met.
    // We assume CTC is mapped to a range, and AY is mapped to another.
    // For this implementation, we derive control signals based on typical Z80 CTC/AY mapping patterns
    // adapted to the specific requirements in the prompt.
    
    wire is_ctc_access = (addr[1:0] == 2'b00) && (addr[15:4] == 4'hF8); // Example mapping F800-F803
    wire is_ay_access  = (addr == 16'hF8FF); // Specific address mentioned for reset, often used for AY control too
    
    // Soft Reset Logic
    // "soft_reset signal is asserted when specific conditions involving the enable (ena), 
    // IORQ (iorq_n), and M1 (m1_n) signals alongside a specific address (16'hF8FF) are met."
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            soft_reset <= 1'b0;
        end else if (ena && !iorq_n && !m1_n && (addr == 16'hF8FF)) begin
            soft_reset <= 1'b1;
        end else begin
            soft_reset <= 1'b0;
        end
    end

    // Global Reset (Hardware + Soft)
    wire sys_reset = reset || soft_reset;

    // Chip Select Logic
    // ctc_ce_n: Active low Chip Enable for CTC
    // ay_sel: Select for AY chips
    always @(*) begin
        // CTC is typically accessed on low A1:A0 for channels, or control register
        if (!iorq_n && !wr_n && (addr[15:4] == 4'hF8) && (addr[1:0] < 2'b11)) 
            ctc_ce_n = 1'b0;
        else
            ctc_ce_n = 1'b1;

        // AY Selection: Often triggered by specific address or data pattern.
        // Here we enable AY if accessing the specific control address or if CTC isn't selected.
        // Assuming standard multiplexed bus approach for AY.
        if (!iorq_n && !wr_n && (addr == 16'hF8FF))
            ay_sel = 1'b1;
        else
            ay_sel = 1'b0;
    end

    // ------------------------------------------------------------------------
    // Z80 CTC Implementation
    // ------------------------------------------------------------------------
    
    // CTC Data Bus Output
    assign dout = ctc_dout;
    
    reg [7:0] ctc_dout;
    reg       ctc_int_n_reg;
    reg       nmi_reg;

    // Interrupt Logic
    assign int_n = ctc_int_n_reg;
    assign nmi   = nmi_reg;

    // CTC Process
    always @(posedge clock or posedge sys_reset) begin
        integer i;
        if (sys_reset) begin
            for (i = 0; i < 4; i = i + 1)
                ctc_reg[i] <= 8'h00;
            ctc_control    <= 8'h00;
            ctc_int_enable <= 1'b0;
            ctc_int_pending<= 1'b0;
            ctc_channel_select <= 4'd0;
            ctc_dout       <= 8'h00;
            ctc_int_n_reg  <= 1'b1; // Active low, idle high
            nmi_reg        <= 1'b0;
        end else if (ena) begin
            // Default hold
            ctc_dout <= 8'hFF; // High-Z equivalent or default
            
            // Write Cycle
            if (!iorq_n && !wr_n && !ctc_ce_n) begin
                if (addr[1:0] == 2'b11) begin
                    // Control Register Write
                    if (din[7]) begin
                        // Control Word
                        ctc_control <= din;
                        ctc_channel_select <= din[5:4];
                        if (din[0]) ctc_int_enable <= 1'b1; // IEI/IEO logic simplified
                    end else begin
                        // Time Constant for selected channel
                        ctc_reg[ctc_channel_select] <= din;
                    end
                end else begin
                    // Channel Register Write (Direct)
                    ctc_reg[addr[1:0]] <= din;
                end
            end
            
            // Read Cycle
            if (!iorq_n && !rd_n && !ctc_ce_n) begin
                if (addr[1:0] == 2'b11) begin
                    ctc_dout <= ctc_control;
                end else begin
                    ctc_dout <= ctc_reg[addr[1:0]];
                end
            end
            
            // CPU Data Input Override (as per spec: "Assigning the CPU data input (cpu_di) to ctc_dout under specific conditions")
            // Spec implies pass-through or specific interrupt ack behavior.
            if (!iorq_n && !rd_n && (addr == 16'hFF)) begin // Example condition for INT ACK
                 ctc_dout <= cpu_di; 
            end

            // Interrupt Generation Simulation
            // In a real CTC, counters decrement. Here we simulate based on spec requirements.
            // If any channel triggers, pull INT low.
            if (ctc_int_enable && ctc_int_pending) begin
                ctc_int_n_reg <= 1'b0;
            end else begin
                ctc_int_n_reg <= 1'b1;
            end
            
            // NMI Logic (Cursor based as per input)
            if (cursor)
                nmi_reg <= 1'b1;
            else
                nmi_reg <= 1'b0;
                
            // Simple decrement simulation for demo purposes if enabled
            // Real implementation requires clock dividers and downcounters per channel.
            // For synthesizable brevity matching spec logic flow:
            if (ctc_reg[0] != 8'h00)
                ctc_reg[0] <= ctc_reg[0] - 1;
            else if (ctc_int_enable)
                ctc_int_pending <= 1'b1;
        end
    end

    // ------------------------------------------------------------------------
    // YM2149 (PSG) Instantiation
    // ------------------------------------------------------------------------

    // Bus Control Signals for Left PSG
    assign ym_bdir_left = (!iorq_n && !wr_n && ay_sel);
    assign ym_bc1_left  = addr[0]; // A0 selects Register/Data

    // Bus Control Signals for Right PSG
    assign ym_bdir_right = (!iorq_n && !wr_n && ay_sel);
    assign ym_bc1_right  = addr[0];

    // Left Channel PSG
    ym2149 psg_left (
        .clock      (clock),
        .reset      (sys_reset),
        .ena        (ena),
        .din        (din),
        .bdir       (ym_bdir_left),
        .bc1        (ym_bc1_left),
        .sel        (1'b1), // Always enabled if selected by bus
        .chan_a     (chl_a),
        .chan_b     (chl_b),
        .chan_c     (chl_c),
        .audio_out  ()      // Unused raw mix
    );

    // Right Channel PSG
    ym2149 psg_right (
        .clock      (clock),
        .reset      (sys_reset),
        .ena        (ena),
        .din        (din),
        .bdir       (ym_bdir_right),
        .bc1        (ym_bc1_right),
        .sel        (1'b1),
        .chan_a     (chr_a),
        .chan_b     (chr_b),
        .chan_c     (chr_c),
        .audio_out  ()
    );

    // ------------------------------------------------------------------------
    // Audio Mixing
    // ------------------------------------------------------------------------
    
    // Sum channels. 3 channels * 8-bit max = 24 bits max, but we saturate/clamp to 10 bits for output DAC
    always @(*) begin
        // Left Mix
        audio_l_sum = {2'b00, chl_a} + {2'b00, chl_b} + {2'b00, chl_c};
        // Clamp to 255 (8-bit)
        if (audio_l_sum > 10'd255)
            audio_l = 8'd255;
        else
            audio_l = audio_l_sum[7:0];

        // Right Mix
        audio_r_sum = {2'b00, chr_a} + {2'b00, chr_b} + {2'b00, chr_c};
        // Clamp to 255 (8-bit)
        if (audio_r_sum > 10'd255)
            audio_r = 8'd255;
        else
            audio_r = audio_r_sum[7:0];
    end

endmodule

// ============================================================================
// Helper Module: YM2149 (AY-3-8910 Compatible)
// Simplified for synthesis and integration.
// ============================================================================

module ym2149
(
    input         clock,
    input         reset,
    input         ena,
    input   [7:0] din,
    input         bdir,
    input         bc1,
    input         sel,
    output  [7:0] chan_a,
    output  [7:0] chan_b,
    output  [7:0] chan_c,
    output  [7:0] audio_out
);

    // Register File
    reg [7:0] regs [0:13];
    reg [3:0] addr_reg;
    reg       write_mode;
    
    // Tone Generators
    reg [11:0] tone_cnt[0:2];
    reg        tone_state[0:2];
    
    // Envelope
    reg [15:0] env_cnt;
    reg [7:0]  env_vol;
    reg        env_hold;
    reg        env_alt;
    reg        env_inc;

    // Output Latches
    reg [7:0] out_a, out_b, out_c;

    assign chan_a = out_a;
    assign chan_b = out_b;
    assign chan_c = out_c;
    assign audio_out = 8'd0; // Not used in dual config

    // Bus Interface Logic
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            integer i;
            for (i=0; i<=13; i=i+1) regs[i] <= 8'd0;
            addr_reg <= 4'd0;
            write_mode <= 1'b0;
        end else if (ena && sel) begin
            if (bdir) begin
                if (bc1) begin
                    // Latch Address
                    addr_reg <= din[3:0];
                    write_mode <= 1'b0;
                end else begin
                    // Write Data
                    if (addr_reg <= 13) begin
                        regs[addr_reg] <= din;
                    end
                    write_mode <= 1'b1;
                end
            end
            // Read mode handling omitted for brevity as primarily write-driven for audio gen
        end
    end

    // Audio Generation Logic
    always @(posedge clock or posedge reset) begin
        integer ch;
        if (reset) begin
            for (ch=0; ch<3; ch=ch+1) begin
                tone_cnt[ch] <= 12'd0;
                tone_state[ch] <= 1'b0;
            end
            env_cnt <= 16'd0;
            env_vol <= 8'd0;
            out_a <= 8'd0; out_b <= 8'd0; out_c <= 8'd0;
        end else if (ena) begin
            // Clock divider for audio (Simplified: assuming clock is appropriate or divided internally)
            // In real hardware, this runs at a fraction of the CPU clock.
            // Here we toggle based on register values for demonstration.
            
            for (ch=0; ch<3; ch=ch+1) begin
                // Tone Period
                // Reg 0,2,4 (Low), Reg 1,3,5 (High)
                // Period = Reg * 16 (approx)
                if (tone_cnt[ch] == 12'd0) begin
                    tone_cnt[ch] <= {regs[ch*2+1][3:0], regs[ch*2]};
                    if ({regs[ch*2+1][3:0], regs[ch*2]} != 12'd0)
                        tone_state[ch] <= ~tone_state[ch];
                end else begin
                    tone_cnt[ch] <= tone_cnt[ch] - 1;
                end
            end

            // Envelope Generator (Simplified)
            if (env_cnt == 16'd0) begin
                env_cnt <= {regs[12], regs[11]}; // Period
                // Update Envelope Shape
                if (env_inc) env_vol <= env_vol + 1;
                else         env_vol <= env_vol - 1;
                
                if (env_vol == 8'd0 || env_vol == 8'd31) begin
                    if (env_hold) env_vol <= env_vol; // Hold
                    else begin
                        env_inc <= ~env_inc;
                        if (env_alt) env_inc <= ~env_inc; // Alternate
                    end
                end
            end else begin
                env_cnt <= env_cnt - 1;
            end

            // Mixer & Output
            // Channel A
            if (regs[7][0]) out_a <= 8'd0; // Mute
            else if (!tone_state[0]) out_a <= 8'd0; // Tone Low
            else out_a <= (regs[8][4]) ? env_vol : {4'd15, 4'd0}; // Mix Envelope or Fixed

            // Channel B
            if (regs[7][1]) out_b <= 8'd0;
            else if (!tone_state[1]) out_b <= 8'd0;
            else out_b <= (regs[9][4]) ? env_vol : {4'd15, 4'd0};

            // Channel C
            if (regs[7][2]) out_c <= 8'd0;
            else if (!tone_state[2]) out_c <= 8'd0;
            else out_c <= (regs[10][4]) ? env_vol : {4'd15, 4'd0};
            
            // Scale output to 0-255 range roughly
            out_a <= (out_a == 8'd0) ? 8'd0 : (out_a << 4);
            out_b <= (out_b == 8'd0) ? 8'd0 : (out_b << 4);
            out_c <= (out_c == 8'd0) ? 8'd0 : (out_c << 4);
        end
    end

endmodule
