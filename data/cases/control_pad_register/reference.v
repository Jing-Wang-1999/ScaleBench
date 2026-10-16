module control_pad_register (
    rd,
    zero,
    clk,
    rst_,
    opcode,
    sel,
    data_e,
    halt,
    inc_pc,
    ld_pc,
    ld_ac,
    ld_ir,
    wr
);
output rd;
input zero;
input clk;
input rst_;
input [2:0] opcode;
output sel;
output data_e;
output halt;
output inc_pc;
output ld_pc;
output ld_ac;
output ld_ir;
output wr;

reg i_control_state_2_;
reg n18;
reg n3;
reg n4;
reg n19;

wire [2:0] opcode_pad = opcode;
wire rst_pad = rst_;
wire zero_pad = zero;

wire CTS_clk_CTO_delay31;
assign CTS_clk_CTO_delay31 = clk;  // Assuming it's a direct delay for simplicity

wire wr_pad;
assign wr = wr_pad;
wire data_e_pad;
assign data_e = data_e_pad;
wire ld_ac_pad;
assign ld_ac = ld_ac_pad;
wire ld_pc_pad;
assign ld_pc = ld_pc_pad;
wire inc_pc_pad;
assign inc_pc = inc_pc_pad;
wire halt_pad;
assign halt = halt_pad;
wire sel_pad;
assign sel = sel_pad;
wire rd_pad;
assign rd = rd_pad;

wire n1;
wire n2;
wire n3;
wire n4;
wire n5;
wire n7;
wire n8;
wire n9;
wire n11;
wire n12;
wire n14;
wire n15;
wire n16;
wire n17;
wire n18;
wire n19;
wire n20;

always @(posedge CTS_clk_CTO_delay31 or negedge rst_pad) begin
    if (!rst_pad) begin
        i_control_state_2_ <= 0;
        n18 <= 0;
        n3 <= 0;
    end else begin
        i_control_state_2_ <= i_control_N14;
        n18 <= sel_pad;
        n3 <= i_control_N21;
    end
end

assign n1 = ~opcode_pad[0];
assign wr_pad = ~(opcode_pad[0] | n5);
assign n5 = n11 & opcode_pad[1] & opcode_pad[2];
assign n8 = ~((opcode_pad[2] & opcode_pad[1]) | (opcode_pad[2] & opcode_pad[1]));
assign n9 = n7 & ~n20;
assign sel_pad = n9 | ~n20;
assign data_e_pad = ~(n8 | n9);
assign ld_ac_pad = n8 & n11;
assign n11 = i_control_state_2_ | n9;
assign n12 = n18 & n20;
assign inc_pc_pad = n12 | (n1 & ~(n5 | n15));
assign n14 = opcode_pad[1] | opcode_pad[2];
assign halt_pad = ~(n14 | (opcode_pad[0] & n12));
assign ld_pc_pad = n9 | n16;
assign n16 = opcode_pad[0] & opcode_pad[2] & opcode_pad[1];
assign n17 = (~(i_control_state_2_ & n3 & n4)) | n8;
assign rd_pad = ~(n7 & (~i_control_state_2_ | n3 | n4));
assign n7 = n18 & n3;
assign n20 = ~n19 & ~n3;
assign n9 = n3 & n4;
assign i_control_N14 = n7 & ~n20;
assign i_control_N21 = (~(n19 & n4)) | (i_control_state_2_ & n18);
assign n19 = i_control_state_2_;

endmodule