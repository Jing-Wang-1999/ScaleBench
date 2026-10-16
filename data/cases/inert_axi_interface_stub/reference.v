module inert_axi_interface_stub (
  input aclk,
  input aresetn,
  input [31:0] s_axi_awaddr,
  input [2:0] s_axi_awprot,
  input s_axi_awvalid,
  output s_axi_awready,
  input [31:0] s_axi_wdata,
  input [3:0] s_axi_wstrb,
  input s_axi_wvalid,
  output s_axi_wready,
  output [1:0] s_axi_bresp,
  output s_axi_bvalid,
  input s_axi_bready,
  input [31:0] s_axi_araddr,
  input [2:0] s_axi_arprot,
  input s_axi_arvalid,
  output s_axi_arready,
  output [31:0] s_axi_rdata,
  output [1:0] s_axi_rresp,
  output s_axi_rvalid,
  input s_axi_rready,
  output [223:0] m_axi_awaddr,
  output [20:0] m_axi_awprot,
  output [6:0] m_axi_awvalid,
  input [6:0] m_axi_awready,
  output [223:0] m_axi_wdata,
  output [27:0] m_axi_wstrb,
  output [6:0] m_axi_wvalid,
  input [6:0] m_axi_wready,
  input [13:0] m_axi_bresp,
  input [6:0] m_axi_bvalid,
  output [6:0] m_axi_bready,
  output [223:0] m_axi_araddr,
  output [20:0] m_axi_arprot,
  output [6:0] m_axi_arvalid,
  input [6:0] m_axi_arready,
  input [223:0] m_axi_rdata,
  input [13:0] m_axi_rresp,
  input [6:0] m_axi_rvalid,
  output [6:0] m_axi_rready
);

  assign s_axi_awready = 0;
  assign s_axi_wready = 0;
  assign s_axi_bresp = 2'b00;
  assign s_axi_bvalid = 0;
  assign s_axi_arready = 0;
  assign s_axi_rdata = 32'h00000000;
  assign s_axi_rresp = 2'b00;
  assign s_axi_rvalid = 0;
  assign m_axi_awaddr = 224'h000000000000000000000000000000000000000000000000000000000000;
  assign m_axi_awprot = 21'h000000;
  assign m_axi_awvalid = 7'b0000000;
  assign m_axi_wdata = 224'h000000000000000000000000000000000000000000000000000000000000;
  assign m_axi_wstrb = 28'h0000000;
  assign m_axi_wvalid = 7'b0000000;
  assign m_axi_bready = 7'b0000000;
  assign m_axi_araddr = 224'h000000000000000000000000000000000000000000000000000000000000;
  assign m_axi_arprot = 21'h000000;
  assign m_axi_arvalid = 7'b0000000;
  assign m_axi_rready = 7'b0000000;

endmodule