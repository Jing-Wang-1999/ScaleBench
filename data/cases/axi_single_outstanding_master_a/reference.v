module axi_single_outstanding_master_a (
    input clk,
    output [63:0] m_axi_araddr,
    output [1:0] m_axi_arburst,
    output [3:0] m_axi_arcache,
    output [5:0] m_axi_arid,
    output [7:0] m_axi_arlen,
    output [1:0] m_axi_arlock,
    output [3:0] m_axi_arqos,
    input m_axi_arready,
    output [3:0] m_axi_arregion,
    output [2:0] m_axi_arsize,
    output m_axi_arvalid,
    output [63:0] m_axi_awaddr,
    output [5:0] m_axi_awid,
    output [7:0] m_axi_awlen,
    input m_axi_awready,
    output [2:0] m_axi_awsize,
    output m_axi_awvalid,
    output m_axi_bready,
    input [1:0] m_axi_bresp,
    input m_axi_bvalid,
    input [63:0] m_axi_rdata,
    input [5:0] m_axi_rid,
    input m_axi_rlast,
    output m_axi_rready,
    input [1:0] m_axi_rresp,
    input m_axi_rvalid,
    output [63:0] m_axi_wdata,
    output m_axi_wlast,
    input m_axi_wready,
    output [7:0] m_axi_wstrb,
    output m_axi_wvalid,
    output [63:0] m_axis_rd_tdata,
    output [7:0] m_axis_rd_tkeep,
    output m_axis_rd_tlast,
    input m_axis_rd_tready,
    output [7:0] m_axis_rd_tstrb,
    output m_axis_rd_tvalid,
    input [63:0] rd_baseAddr,
    output rd_done,
    input [31:0] rd_req_din,
    output rd_req_full_n,
    input rd_req_wr_en,
    input rd_start,
    input rst_n,
    input [63:0] s_axis_wr_tdata,
    output s_axis_wr_tready,
    input s_axis_wr_tvalid,
    input [63:0] wr_baseAddr,
    output wr_done,
    input [7:0] wr_len,
    input wr_start
);

    reg rd_start_delayed;
    reg read_address_valid;
    reg read_data_active;
    reg [63:0] read_address;
    reg [7:0] read_length;
    reg read_done_pulse;

    reg wr_start_delayed;
    reg write_address_valid;
    reg write_data_active;
    reg write_response_active;
    reg [63:0] write_address;
    reg [7:0] write_length;
    reg [7:0] write_beats_sent;
    reg write_data_valid;
    reg [63:0] write_data;
    reg write_last;
    reg write_done_pulse;

    wire read_start_pulse;
    wire write_start_pulse;
    wire read_idle;
    wire write_idle;

    assign read_start_pulse = rd_start & ~rd_start_delayed;
    assign write_start_pulse = wr_start & ~wr_start_delayed;
    assign read_idle = ~read_address_valid & ~read_data_active;
    assign write_idle = ~write_address_valid & ~write_data_active
                      & ~write_response_active & ~write_data_valid;

    assign m_axi_araddr = read_address;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arcache = 4'b0000;
    assign m_axi_arid = 6'b000000;
    assign m_axi_arlen = read_length;
    assign m_axi_arlock = 2'b00;
    assign m_axi_arqos = 4'b0000;
    assign m_axi_arregion = 4'b0000;
    assign m_axi_arsize = 3'b011;
    assign m_axi_arvalid = read_address_valid;

    assign m_axi_rready = read_data_active & m_axis_rd_tready;
    assign m_axis_rd_tdata = m_axi_rdata;
    assign m_axis_rd_tkeep = 8'hff;
    assign m_axis_rd_tlast = m_axi_rlast;
    assign m_axis_rd_tstrb = 8'hff;
    assign m_axis_rd_tvalid = read_data_active & m_axi_rvalid;
    assign rd_done = read_done_pulse;
    assign rd_req_full_n = read_idle;

    assign m_axi_awaddr = write_address;
    assign m_axi_awid = 6'b000000;
    assign m_axi_awlen = write_length;
    assign m_axi_awsize = 3'b011;
    assign m_axi_awvalid = write_address_valid;

    assign m_axi_wdata = write_data;
    assign m_axi_wlast = write_last;
    assign m_axi_wstrb = 8'hff;
    assign m_axi_wvalid = write_data_valid;
    assign s_axis_wr_tready = write_data_active & ~write_data_valid;

    assign m_axi_bready = write_response_active;
    assign wr_done = write_done_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_start_delayed <= 1'b0;
            read_address_valid <= 1'b0;
            read_data_active <= 1'b0;
            read_address <= 64'b0;
            read_length <= 8'b0;
            read_done_pulse <= 1'b0;
        end else begin
            rd_start_delayed <= rd_start;
            read_done_pulse <= 1'b0;

            if (read_start_pulse && rd_req_wr_en && read_idle) begin
                read_address <= rd_baseAddr;
                read_length <= rd_req_din[7:0];
                read_address_valid <= 1'b1;
            end

            if (read_address_valid && m_axi_arready) begin
                read_address_valid <= 1'b0;
                read_data_active <= 1'b1;
            end

            if (read_data_active && m_axi_rvalid
                    && m_axis_rd_tready && m_axi_rlast) begin
                read_data_active <= 1'b0;
                read_done_pulse <= 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_start_delayed <= 1'b0;
            write_address_valid <= 1'b0;
            write_data_active <= 1'b0;
            write_response_active <= 1'b0;
            write_address <= 64'b0;
            write_length <= 8'b0;
            write_beats_sent <= 8'b0;
            write_data_valid <= 1'b0;
            write_data <= 64'b0;
            write_last <= 1'b0;
            write_done_pulse <= 1'b0;
        end else begin
            wr_start_delayed <= wr_start;
            write_done_pulse <= 1'b0;

            if (write_start_pulse && write_idle) begin
                write_address <= wr_baseAddr;
                write_length <= wr_len;
                write_address_valid <= 1'b1;
            end

            if (write_address_valid && m_axi_awready) begin
                write_address_valid <= 1'b0;
                write_data_active <= 1'b1;
                write_beats_sent <= 8'b0;
            end

            if (write_data_active && !write_data_valid
                    && s_axis_wr_tvalid) begin
                write_data <= s_axis_wr_tdata;
                write_last <= (write_beats_sent == write_length);
                write_data_valid <= 1'b1;
            end

            if (write_data_valid && m_axi_wready) begin
                write_data_valid <= 1'b0;
                if (write_last) begin
                    write_data_active <= 1'b0;
                    write_response_active <= 1'b1;
                end else begin
                    write_beats_sent <= write_beats_sent + 1'b1;
                end
            end

            if (write_response_active && m_axi_bvalid) begin
                write_response_active <= 1'b0;
                write_done_pulse <= 1'b1;
            end
        end
    end

    wire unused_read_metadata;
    wire unused_write_response;
    assign unused_read_metadata = ^{m_axi_rid, m_axi_rresp};
    assign unused_write_response = ^m_axi_bresp;

endmodule
