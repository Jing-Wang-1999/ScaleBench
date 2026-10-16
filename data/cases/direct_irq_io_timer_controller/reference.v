module direct_irq_io_timer_controller
(
    input        clk,
    input        clk7_en,
    input        clk7n_en,
    input        aen,
    input        rd,
    input        wr,
    input        reset,
    input  [3:0] rs,
    input  [7:0] data_in,
    output reg [7:0] data_out,
    input        tick,
    input        eclk,
    output       irq,
    input  [7:2] porta_in,
    output [3:0] porta_out,
    input  [7:0] portb_in,

    input        kms_level,
    input  [1:0] kbd_mouse_type,
    input  [7:0] kbd_mouse_data,
    output       freeze,
    input        hrtmon_en
);

    wire read_access = aen && rd && !wr;
    wire write_access = aen && wr;

    reg kms_level_d;
    reg keystrobe;
    reg [7:0] serial_data;
    reg freeze_reg;

    reg [3:0] porta_data;
    reg [7:0] porta_direction;
    reg [7:0] portb_direction;
    reg [7:2] porta_input_sample;

    reg [7:0] interrupt_control;
    reg [15:0] timer_a;
    reg [15:0] timer_b;
    reg [23:0] timer_d;

    wire timer_a_terminal = (timer_a == 16'hffff);
    wire timer_b_terminal = (timer_b == 16'hffff);
    wire timer_d_terminal = (timer_d == 24'hffffff);

    assign freeze = freeze_reg;
    assign porta_out = {
        (~porta_direction[7:6]) | porta_data[3:2],
        (~porta_direction[1:0]) | porta_data[1:0]
    };
    assign irq = timer_a_terminal || timer_b_terminal ||
                 timer_d_terminal || keystrobe;

    // Retain tick and eclk for interface compatibility. Timers in this
    // direct-interrupt variant advance from clk7_en.
    wire unused_inputs = tick ^ eclk;

    always @(posedge clk) begin
        if (reset) begin
            kms_level_d <= 1'b0;
            keystrobe <= 1'b0;
        end else begin
            keystrobe <= 1'b0;
            if (clk7n_en) begin
                keystrobe <= (kms_level != kms_level_d) &&
                             (kbd_mouse_type == 2'b10);
                kms_level_d <= kms_level;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            serial_data <= 8'h00;
            freeze_reg <= 1'b0;
        end else if (clk7_en) begin
            if (keystrobe) begin
                serial_data <= ~{kbd_mouse_data[6:0], kbd_mouse_data[7]};
                freeze_reg <= hrtmon_en && (kbd_mouse_data == 8'h5f);
            end else if (write_access && (rs == 4'hc)) begin
                serial_data <= data_in;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            porta_input_sample <= 6'h00;
            porta_data <= 4'h0;
            porta_direction <= 8'h00;
            portb_direction <= 8'h00;
        end else if (clk7_en) begin
            porta_input_sample <= porta_in;
            if (write_access && (rs == 4'h0))
                porta_data <= {data_in[7:6], data_in[1:0]};
            if (write_access && (rs == 4'h2))
                porta_direction <= data_in;
            if (write_access && (rs == 4'h3))
                portb_direction <= data_in;
        end
    end

    always @(posedge clk) begin
        if (reset)
            interrupt_control <= 8'h00;
        else if (write_access && (rs == 4'hd))
            interrupt_control <= data_in;
    end

    always @(posedge clk) begin
        if (reset) begin
            timer_a <= 16'h0000;
        end else if (clk7_en) begin
            if (write_access && (rs == 4'h4))
                timer_a[7:0] <= data_in;
            else if (write_access && (rs == 4'h5))
                timer_a[15:8] <= data_in;
            else
                timer_a <= timer_a + 16'd1;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            timer_b <= 16'h0000;
        end else if (clk7_en) begin
            if (write_access && (rs == 4'h6))
                timer_b[7:0] <= data_in;
            else if (write_access && (rs == 4'h7))
                timer_b[15:8] <= data_in;
            else
                timer_b <= timer_b + 16'd1;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            timer_d <= 24'h000000;
        end else if (clk7_en) begin
            if (write_access && (rs == 4'h8))
                timer_d[7:0] <= data_in;
            else if (write_access && (rs == 4'h9))
                timer_d[15:8] <= data_in;
            else if (write_access && (rs == 4'ha))
                timer_d[23:16] <= data_in;
            else
                timer_d <= timer_d + 24'd1;
        end
    end

    always @(*) begin
        data_out = 8'h00;
        if (read_access) begin
            case (rs)
                4'h0: data_out = {porta_input_sample, porta_out[1:0]};
                4'h1: data_out = portb_in;
                4'h2: data_out = porta_direction;
                4'h3: data_out = portb_direction;
                4'h4: data_out = timer_a[7:0];
                4'h5: data_out = timer_a[15:8];
                4'h6: data_out = timer_b[7:0];
                4'h7: data_out = timer_b[15:8];
                4'h8: data_out = timer_d[7:0];
                4'h9: data_out = timer_d[15:8];
                4'ha: data_out = timer_d[23:16];
                4'hc: data_out = serial_data;
                4'hd: data_out = interrupt_control;
                default: data_out = 8'h00;
            endcase
        end
    end

endmodule
