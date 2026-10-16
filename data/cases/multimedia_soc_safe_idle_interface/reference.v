module multimedia_soc_safe_idle_interface (
  input            sys_clk,

  output  [14:0]   ddr3_a,
  output  [ 2:0]   ddr3_ba,
  output           ddr3_reset_n,
  output           ddr3_ck_p,
  output           ddr3_ck_n,
  output           ddr3_cke,
  output           ddr3_cs_n,
  output           ddr3_ras_n,
  output           ddr3_cas_n,
  output           ddr3_we_n,
  inout   [31:0]   ddr3_dq,
  inout   [ 3:0]   ddr3_dqs_p,
  inout   [ 3:0]   ddr3_dqs_n,
  output  [ 3:0]   ddr3_dm,
  output           ddr3_odt,
  input            ddr3_rzq,

  output           eth1_tx_clk,
  output           eth1_tx_ctl,
  output  [ 3:0]   eth1_tx_d,
  input            eth1_rx_clk,
  input            eth1_rx_ctl,
  input   [ 3:0]   eth1_rx_d,
  output           eth1_mdc,
  inout            eth1_mdio,

  output           sdio_clk,
  inout            sdio_cmd,
  inout   [ 3:0]   sdio_d,

  output           spim1_ss0,
  output           spim1_clk,
  output           spim1_mosi,
  input            spim1_miso,

  input            usb1_clk,
  output           usb1_stp,
  input            usb1_dir,
  input            usb1_nxt,
  inout   [ 7:0]   usb1_d,

  input            uart0_rx,
  output           uart0_tx,
  inout            hps_conv_usb_n,

  output  [ 7:0]   gpio_bd_o,
  input   [ 5:0]   gpio_bd_i,

  output           hdmi_out_clk,
  output           hdmi_vsync,
  output           hdmi_hsync,
  output           hdmi_data_e,
  output  [23:0]   hdmi_data,

  inout            hdmi_i2c_scl,
  inout            hdmi_i2c_sda,

  input            adc_clk_in,
  input            adc_ready_in,
  input   [ 3:0]   adc_data_in,
  output           spi_csn,
  output           spi_clk,
  output           spi_mosi,
  input            spi_miso,
  output           start_n,
  output           sdp_convst,
  output           sdp_mclk,
  output           reset_n
);

  // The omitted SoC subsystem is represented by deterministic safe-idle pin
  // values. No signal declared as an input is driven by this module.
  assign ddr3_a       = 15'b0;
  assign ddr3_ba      = 3'b0;
  assign ddr3_reset_n = 1'b1;
  assign ddr3_ck_p    = 1'b0;
  assign ddr3_ck_n    = 1'b0;
  assign ddr3_cke     = 1'b0;
  assign ddr3_cs_n    = 1'b1;
  assign ddr3_ras_n   = 1'b1;
  assign ddr3_cas_n   = 1'b1;
  assign ddr3_we_n    = 1'b1;
  assign ddr3_dq      = 32'bz;
  assign ddr3_dqs_p   = 4'bz;
  assign ddr3_dqs_n   = 4'bz;
  assign ddr3_dm      = 4'b0;
  assign ddr3_odt     = 1'b0;

  assign eth1_tx_clk = 1'b0;
  assign eth1_tx_ctl = 1'b0;
  assign eth1_tx_d   = 4'b0;
  assign eth1_mdc    = 1'b0;
  assign eth1_mdio   = 1'bz;

  assign sdio_clk = 1'b0;
  assign sdio_cmd = 1'bz;
  assign sdio_d   = 4'bz;

  assign spim1_ss0  = 1'b1;
  assign spim1_clk  = 1'b0;
  assign spim1_mosi = 1'b0;

  assign usb1_stp = 1'b0;
  assign usb1_d   = 8'bz;

  assign uart0_tx       = 1'b1;
  assign hps_conv_usb_n = 1'bz;
  assign gpio_bd_o      = 8'b0;

  assign hdmi_out_clk = 1'b0;
  assign hdmi_vsync   = 1'b0;
  assign hdmi_hsync   = 1'b0;
  assign hdmi_data_e  = 1'b0;
  assign hdmi_data    = 24'b0;
  assign hdmi_i2c_scl = 1'bz;
  assign hdmi_i2c_sda = 1'bz;

  assign spi_csn  = 1'b1;
  assign spi_clk  = 1'b0;
  assign spi_mosi = 1'b0;

  assign start_n    = 1'b1;
  assign sdp_convst = 1'b0;
  assign sdp_mclk   = 1'b0;
  assign reset_n    = 1'b1;

endmodule
