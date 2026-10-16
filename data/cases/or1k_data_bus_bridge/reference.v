module or1k_data_bus_bridge (
    clk, rst,

    dcsb_dat_o, dcsb_adr_o, dcsb_cyc_o, dcsb_stb_o, dcsb_we_o, dcsb_sel_o, dcsb_cab_o,
    dcsb_dat_i, dcsb_ack_i, dcsb_err_i,

    dc_en,
    dcqmem_adr_i, dcqmem_cycstb_i, dcqmem_ci_i,
    dcqmem_we_i, dcqmem_sel_i, dcqmem_tag_i, dcqmem_dat_i,
    dcqmem_dat_o, dcqmem_ack_o, dcqmem_rty_o, dcqmem_err_o, dcqmem_tag_o,

    spr_cs, spr_write, spr_dat_i
);

  parameter dw = 32;

  input               clk;
  input               rst;

  output  [dw-1:0]    dcsb_dat_o;
  output  [31:0]      dcsb_adr_o;
  output              dcsb_cyc_o;
  output              dcsb_stb_o;
  output              dcsb_we_o;
  output  [3:0]       dcsb_sel_o;
  output              dcsb_cab_o;
  input   [dw-1:0]    dcsb_dat_i;
  input               dcsb_ack_i;
  input               dcsb_err_i;

  input               dc_en;
  input   [31:0]      dcqmem_adr_i;
  input               dcqmem_cycstb_i;
  input               dcqmem_ci_i;
  input               dcqmem_we_i;
  input   [3:0]       dcqmem_sel_i;
  input   [3:0]       dcqmem_tag_i;
  input   [dw-1:0]    dcqmem_dat_i;
  output  [dw-1:0]    dcqmem_dat_o;
  output              dcqmem_ack_o;
  output              dcqmem_rty_o;
  output              dcqmem_err_o;
  output  [3:0]       dcqmem_tag_o;

  input               spr_cs;
  input               spr_write;
  input   [31:0]      spr_dat_i;

  // This reduced wrapper is a transparent bridge. It intentionally contains
  // no cache RAM, tag RAM, or cache-control state machine.
  assign dcsb_dat_o = dcqmem_dat_i;
  assign dcsb_adr_o = dcqmem_adr_i;
  assign dcsb_cyc_o = dcqmem_cycstb_i;
  assign dcsb_stb_o = dcqmem_cycstb_i;
  assign dcsb_we_o  = dcqmem_we_i;
  assign dcsb_sel_o = dcqmem_sel_i;
  assign dcsb_cab_o = 1'b0;

  assign dcqmem_dat_o = dcsb_dat_i;
  assign dcqmem_ack_o = dcsb_ack_i;
  assign dcqmem_rty_o = ~dcsb_ack_i;
  assign dcqmem_err_o = dcsb_err_i;
  assign dcqmem_tag_o = dcsb_err_i ? 4'b1111 : dcqmem_tag_i;

endmodule
