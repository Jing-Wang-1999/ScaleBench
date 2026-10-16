module ps2_wishbone_controller(
    input wire       wb_clk_i,
    input wire       wb_rst_i,
    input wire [7:0] wb_dat_i,
    output wire [7:0] wb_dat_o,
    input wire [0:0] wb_adr_i,
    input wire       wb_stb_i,
    input wire       wb_we_i,
    output wire      wb_ack_o,

    output wire      irq_o,

    inout wire       ps2_clk,
    inout wire       ps2_dat
);

    wire       nrst;
    wire [7:0] ps2_data_o;
    wire [7:0] ps2_data_i;
    wire       ibf_clr;
    wire       obf_set;
    wire       ibf;
    wire       obf;
    wire       frame_err;
    wire       parity_err;
    wire       busy;
    wire       err_clr;
    wire       wdt;

    wire [7:0] status_reg;
    reg  [7:0] control_reg;

    wire irq_rx_enb;
    wire irq_tx_enb;

    // Internal logic previously implemented in the ps2 module
    reg [7:0] ps2_data_buf;
    reg ps2_ibf;
    reg ps2_obf;
    reg ps2_frame_err;
    reg ps2_parity_err;
    reg ps2_busy;
    reg ps2_wdt;

    assign ps2_data_o = ps2_data_buf;
    assign ibf = ps2_ibf;
    assign obf = ps2_obf;
    assign frame_err = ps2_frame_err;
    assign parity_err = ps2_parity_err;
    assign busy = ps2_busy;
    assign wdt = ps2_wdt;

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            ps2_data_buf <= 8'b0;
            ps2_ibf <= 1'b0;
            ps2_obf <= 1'b0;
            ps2_frame_err <= 1'b0;
            ps2_parity_err <= 1'b0;
            ps2_busy <= 1'b0;
            ps2_wdt <= 1'b0;
        end else begin
            if (ibf_clr) ps2_ibf <= 1'b0;
            if (obf_set) ps2_obf <= 1'b1;
            if (err_clr) begin
                ps2_frame_err <= 1'b0;
                ps2_parity_err <= 1'b0;
            end
            if (wb_stb_i & wb_we_i & ~wb_adr_i[0]) begin
                ps2_data_buf <= wb_dat_i;
                ps2_ibf <= 1'b1;
                ps2_busy <= 1'b1;
            end
            if (ps2_obf & ~ps2_ibf) begin
                ps2_busy <= 1'b0;
            end
        end
    end

    // External PS2 logic
    assign ps2_clk = (ps2_busy) ? 1'bz : 1'b0;
    assign ps2_dat = (ps2_busy) ? ps2_data_buf[0] : 1'bz;

    assign nrst = ~wb_rst_i;
    assign err_clr = wb_stb_i & wb_we_i & wb_adr_i & ~wb_dat_i[3];
    assign ibf_clr = wb_stb_i & wb_we_i & wb_adr_i & ~wb_dat_i[0];
    assign obf_set = wb_stb_i & wb_we_i & ~wb_adr_i[0];

    assign status_reg[7] = irq_tx_enb;
    assign status_reg[6] = irq_rx_enb;
    assign status_reg[5:4] = 2'b0;
    assign status_reg[3] = parity_err | frame_err;
    assign status_reg[2] = obf;
    assign status_reg[1] = ibf;
    assign status_reg[0] = busy;

    assign irq_rx_enb = control_reg[6];
    assign irq_tx_enb = control_reg[7];

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            control_reg[7:6] <= 2'b0;
        end else if (wb_stb_i & wb_we_i & wb_adr_i) begin
            control_reg[7:6] <= wb_dat_i[7:6];
        end
    end

    assign wb_dat_o = wb_adr_i[0] ? status_reg : ps2_data_o;
    assign ps2_data_i = wb_dat_i;

    assign irq_o = (ibf & irq_rx_enb) | (~obf & irq_tx_enb);

    assign wb_ack_o = wb_stb_i;

endmodule