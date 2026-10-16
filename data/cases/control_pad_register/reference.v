module control_pad_register (
    output rd,
    input zero,
    input clk,
    input rst_,
    input [2:0] opcode,
    output sel,
    output data_e,
    output halt,
    output inc_pc,
    output ld_pc,
    output ld_ac,
    output ld_ir,
    output wr
);
    reg state;
    reg phase;
    reg history;

    wire n1;
    wire n4;
    wire n5;
    wire n7;
    wire n8;
    wire n9;
    wire n11;
    wire n12;
    wire n15;
    wire n16;
    wire n19;
    wire n20;
    wire next_state;
    wire next_history;

    assign n1 = ~opcode[0];
    assign n4 = zero;
    assign n7 = phase & history;
    assign n19 = state;
    assign n20 = ~n19 & ~history;
    assign n9 = n7 & ~n20;
    assign n8 = ~(opcode[2] & opcode[1]);
    assign n11 = state | n9;
    assign n5 = n11 & opcode[1] & opcode[2];
    assign n12 = phase & n20;
    assign n15 = (~(state & history & n4)) | n8;
    assign n16 = opcode[0] & opcode[2] & opcode[1];

    assign next_state = n7 & ~n20;
    assign next_history = (~(n19 & n4)) | (state & phase);

    assign wr = ~(opcode[0] | n5);
    assign sel = n9 | ~n20;
    assign data_e = ~(n8 | n9);
    assign ld_ac = n8 & n11;
    assign inc_pc = n12 | (n1 & ~(n5 | n15));
    assign halt = ~((opcode[1] | opcode[2]) | (opcode[0] & n12));
    assign ld_pc = n9 | n16;
    assign rd = ~(n7 & (~state | history | n4));
    assign ld_ir = 1'b0;

    always @(posedge clk or negedge rst_) begin
        if (!rst_) begin
            state <= 1'b0;
            phase <= 1'b0;
            history <= 1'b0;
        end else begin
            state <= next_state;
            phase <= sel;
            history <= next_history;
        end
    end
endmodule
