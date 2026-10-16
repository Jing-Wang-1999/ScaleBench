module nios_jtag_debug_control (
    input  [31:0] MonDReg,
    input  [31:0] break_readreg,
    input         clk,
    input         dbrk_hit0_latch,
    input         dbrk_hit1_latch,
    input         dbrk_hit2_latch,
    input         dbrk_hit3_latch,
    input         debugack,
    input         monitor_error,
    input         monitor_ready,
    input         reset_n,
    input         resetlatch,
    input         tracemem_on,
    input  [35:0] tracemem_trcdata,
    input         tracemem_tw,
    input  [6:0]  trc_im_addr,
    input         trc_on,
    input         trc_wrap,
    input         trigbrktype,
    input         trigger_state_1,

    output [37:0] jdo,
    output        jrst_n,
    output        st_ready_test_idle,
    output        take_action_break_a,
    output        take_action_break_b,
    output        take_action_break_c,
    output        take_action_ocimem_a,
    output        take_action_ocimem_b,
    output        take_action_tracectrl,
    output        take_action_tracemem_a,
    output        take_action_tracemem_b,
    output        take_no_action_break_a,
    output        take_no_action_break_b,
    output        take_no_action_break_c,
    output        take_no_action_ocimem_a,
    output        take_no_action_tracemem_a
);

  // Preserve the low 38 bits of the historical 64-bit concatenation without
  // relying on implicit width truncation.
  assign jdo = {MonDReg[5:0], break_readreg};

  assign jrst_n = reset_n & ~resetlatch;
  assign st_ready_test_idle = monitor_ready & ~monitor_error;

  // The absent virtual-JTAG transport cannot request an action. These outputs
  // are explicit constants, so the stub contains no hidden state.
  assign take_action_break_a       = 1'b0;
  assign take_action_break_b       = 1'b0;
  assign take_action_break_c       = 1'b0;
  assign take_action_ocimem_a      = 1'b0;
  assign take_action_ocimem_b      = 1'b0;
  assign take_action_tracectrl     = 1'b0;
  assign take_action_tracemem_a    = 1'b0;
  assign take_action_tracemem_b    = 1'b0;
  assign take_no_action_break_a    = 1'b0;
  assign take_no_action_break_b    = 1'b0;
  assign take_no_action_break_c    = 1'b0;
  assign take_no_action_ocimem_a   = 1'b0;
  assign take_no_action_tracemem_a = 1'b0;

endmodule
