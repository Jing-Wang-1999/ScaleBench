module and_gate(x, y, z);
	input x, y;
	output z;
	assign z = x & y;
endmodule

module mux(sel, src0, src1, z);
	input sel;
	input src0, src1;
	output z;
	assign z = sel ? src1 : src0;
endmodule

module or_gate(x, y, z);
	input x, y;
	output z;
	assign z = x | y;
endmodule

module not_gate(x, z);
	input x;
	output z;
	assign z = ~x;
endmodule

module xor_gate(x, y, z);
	input x, y;
	output z;
	assign z = x ^ y;
endmodule

module set_if_eq(x, y, z);
	input [5:0] x;
	input [5:0] y;
	output z;
	wire [5:0] xored;
	
	genvar i;
	generate
	for (i = 0; i < 6; i = i + 1) begin
		xor_gate xorl(x[i], y[i], xored[i]);
	end
	endgenerate
	
	wire [4:0] ored;
	or_gate or1(xored[0], xored[1], ored[0]);
	or_gate or2(xored[2], xored[3], ored[1]);
	or_gate or3(xored[4], xored[5], ored[2]);
	or_gate or4(ored[0], ored[1], ored[3]);
	or_gate or5(ored[2], ored[3], ored[4]);
	
	not_gate not1(ored[4], z);
endmodule

module decode_func(Op, Fun, func, RegDst);
	input [5:0] Op;
	input [5:0] Fun;
	output [14:0] func; 
	output RegDst;
	
	wire r_type;
	set_if_eq setr(Op, 6'b000000, r_type);
	
	wire [8:0] r_func; 
	set_if_eq addr(Fun, 6'b100000, r_func[8]);
	set_if_eq addur(Fun, 6'b100001, r_func[7]);
	set_if_eq subr(Fun, 6'b100010, r_func[6]);
	set_if_eq subur(Fun, 6'b100011, r_func[5]);
	set_if_eq andr(Fun, 6'b100100, r_func[4]);
	set_if_eq orr(Fun, 6'b100101, r_func[3]);
	set_if_eq sllr(Fun, 6'b000000, r_func[2]);
	set_if_eq sltr(Fun, 6'b101010, r_func[1]);
	set_if_eq sltur(Fun, 6'b101011, r_func[0]);
	
	mux addmux(r_type, 1'b0, r_func[8], func[14]);
	set_if_eq addif(Op, 6'b001000, func[13]);
	mux addumux(r_type, 1'b0, r_func[7], func[12]);
	mux submux(r_type, 1'b0, r_func[6], func[11]);
	mux subumux(r_type, 1'b0, r_func[5], func[10]);
	mux andmux(r_type, 1'b0, r_func[4], func[9]);
	mux ormux(r_type, 1'b0, r_func[3], func[8]);
	mux sllmux(r_type, 1'b0, r_func[2], func[7]);
	set_if_eq lwf(Op, 6'b100011, func[6]);
	set_if_eq swf(Op, 6'b101011, func[5]);
	set_if_eq beqf(Op, 6'b000100, func[4]);
	set_if_eq bnef(Op, 6'b000101, func[3]);
	set_if_eq bgtzf(Op, 6'b000111, func[2]);
	mux sltmux(r_type, 1'b0, r_func[1], func[1]);
	mux sltumux(r_type, 1'b0, r_func[0], func[0]);
	
	wire [1:0] branchors;
	or_gate orb1(func[4], func[3], branchors[1]);
	or_gate orb2(func[2], branchors[1], branchors[0]);
	or_gate ordst(r_type, branchors[0], RegDst);
endmodule

module get_ALUctr(func, ALUctr);
	input [14:0] func;
	output [2:0] ALUctr;
	
	wire alu_and;
	assign alu_and = func[9];
	
	wire alu_or;
	assign alu_or = func[8];
	
	wire alu_fa;
	wire [1:0] alu_fa_or;
	or_gate orfa1(func[6], func[5], alu_fa_or[1]);
	or_gate orfa2(func[14], func[13], alu_fa_or[0]);
	or_gate orfa(alu_fa_or[0], alu_fa_or[1], alu_fa);
	
	wire alu_slt;
	assign alu_slt = func[1];
	
	wire alu_fau, alu_fau_or1;
	assign alu_fau = func[12];
	
	wire alu_sll;
	assign alu_sll = func[7];
	
	wire alu_sub;
	wire [2:0] alu_sub_mid;
	or_gate orsub1(func[11], func[10], alu_sub_mid[2]);
	or_gate orsub2(func[4], func[3], alu_sub_mid[1]);
	or_gate orsub3(func[2], alu_sub_mid[2], alu_sub_mid[0]);
	or_gate orsub4(alu_sub_mid[1], alu_sub_mid[0], alu_sub);
	
	wire alu_sltu;
	assign alu_sltu = func[0];
	
	wire [1:0] or_wires_1;
	or_gate orenc1(alu_or, alu_slt, or_wires_1[1]);
	or_gate orenc2(alu_sll, alu_sltu, or_wires_1[0]);
	or_gate orenc3(or_wires_1[1], or_wires_1[0], ALUctr[0]);
	
	wire [1:0] or_wires_2;
	or_gate orenc4(alu_fa, alu_slt, or_wires_2[1]);
	or_gate orenc5(alu_sub, alu_slt, or_wires_2[0]);
	or_gate orenc6(or_wires_2[1], or_wires_2[0], ALUctr[1]);
	
	wire [1:0] or_wires_3;
	or_gate orenc7(alu_fau, alu_sll, or_wires_3[1]);
	or_gate orenc8(alu_sub, alu_sltu, or_wires_3[0]);
	or_gate orenc9(or_wires_3[1], or_wires_3[0], ALUctr[2]);
endmodule

module control(Op, Fun, equal, sign, nPC_sel, RegWr, RegDst, ExtOp, ALUSrc, ALUctr, MemWr, MemtoReg);
	input [5:0] Op;
	input [5:0] Fun;
	input equal, sign;
	output nPC_sel, RegWr, RegDst, ALUSrc, MemWr, MemtoReg;
	output ExtOp;
	output [2:0] ALUctr;
	
	wire [14:0] func; 
	decode_func getfunc(.Op(Op), .Fun(Fun), .func(func), .RegDst(RegDst));
	get_ALUctr getaluctr(.func(func), .ALUctr(ALUctr));
	
	wire beq_t;
	and_gate beqand(func[4], equal, beq_t);
	wire bne_t, not_equal;
	not_gate noteq(equal, not_equal);
	and_gate bneand(func[3], not_equal, bne_t);
	wire bgtz_t, ltorz, not_ltorz;
	or_gate orltorz(equal, sign, ltorz);
	not_gate notltorz(ltorz, not_ltorz);
	and_gate bgtzand(func[2], not_ltorz, bgtz_t);
	wire branch_or1;
	or_gate branchor1(beq_t, bne_t, branch_or1);
	or_gate branchor2(branch_or1, bgtz_t, nPC_sel);
	
	wire [2:0] reg_wr_mid;
	or_gate regor1(func[2], func[3], reg_wr_mid[1]);
	or_gate regor2(func[4], func[5], reg_wr_mid[0]);
	or_gate regor3(reg_wr_mid[0], reg_wr_mid[1], reg_wr_mid[2]);
	not_gate regwrnot(reg_wr_mid[2], RegWr);
	
	wire extop_mid;
	or_gate extopor1(func[5], func[6], extop_mid);
	or_gate extopor2(extop_mid, func[13], ExtOp);
	
	not_gate alusrcnot(RegDst, ALUSrc);
	
	assign MemWr = func[5];
	assign MemtoReg = func[6];
endmodule

module xr16_processor_core(
	clk, rst, rdy, ud_t, ld_t, udlt_t, int_req, dma_req, zerodma,
    insn, mem_ce, word_nxt, read_nxt, dbus_nxt, dma, addr_nxt, d
);

	parameter		W	= 16;	
	parameter		N	= W-1;	

	input			clk;		
	input			rst;		
	input			rdy;		
	input			ud_t;		
	input			ld_t;		
	input			udlt_t;		
	input			int_req;	
	input			dma_req;	
	input			zerodma;	
	input	[N:0]	insn;		
	output			mem_ce;		
	output			word_nxt;	
	output			read_nxt;	
	output			dbus_nxt;	
	output			dma;		
	output	[N:0]	addr_nxt;	
	inout	[N:0]	d;			

	
	wire		a15;		
	wire		z;			
	wire		n;			
	wire		co;			
	wire		v;			
	wire		rf_we;		
	wire [3:0]	rna;		
	wire [3:0]	rnb;		
	wire		fwd;		
	wire [11:0]	imm;		
	wire		sextimm4;	
	wire		zextimm4;	
	wire		wordimm4;	
	wire		imm12;		
	wire		pipe_ce;	
	wire		b15_4_ce;	
	wire		add;		
	wire		ci;			
	wire [1:0]	logicop;	
	wire		sri;		
	wire		sum_t;		
	wire		logic_t;	
	wire		zeroext_t;	
	wire		shr_t;		
	wire		shl_t;		
	wire		ret_t;		
	wire		branch;		
	wire [7:0]	brdisp;		
	wire		selpc;		
	wire		zeropc;		
	wire		dmapc;		
	wire		pc_ce;		
	wire		ret_ce;		

	
	// Internal logic for control module (Assumption based on typical control unit in a CPU)
	reg	mem_ce_reg, word_nxt_reg, read_nxt_reg, dbus_nxt_reg, dma_reg;
	reg	rf_we_reg;
	reg	branch_reg, selpc_reg, zeropc_reg, dmapc_reg;
	reg	pc_ce_reg, ret_ce_reg;
	
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			mem_ce_reg <= 1'b0;
			word_nxt_reg <= 1'b0;
			read_nxt_reg <= 1'b0;
			dbus_nxt_reg <= 1'b0;
			dma_reg <= 1'b0;
			rf_we_reg <= 1'b0;
			branch_reg <= 1'b0;
			selpc_reg <= 1'b0;
			zeropc_reg <= 1'b0;
			dmapc_reg <= 1'b0;
			pc_ce_reg <= 1'b0;
			ret_ce_reg <= 1'b0;
		end else if (rdy) begin
			// Example simplified control logic
			mem_ce_reg <= insn[0];
			word_nxt_reg <= insn[1];
			read_nxt_reg <= insn[2];
			dbus_nxt_reg <= insn[3];
			dma_reg <= dma_req;
			rf_we_reg <= insn[4];
			branch_reg <= insn[5];
			selpc_reg <= insn[6];
			zeropc_reg <= insn[7];
			dmapc_reg <= insn[8];
			pc_ce_reg <= insn[9];
			ret_ce_reg <= insn[10];
		end
	end
	
	assign mem_ce = mem_ce_reg;
	assign word_nxt = word_nxt_reg;
	assign read_nxt = read_nxt_reg;
	assign dbus_nxt = dbus_nxt_reg;
	assign dma = dma_reg;
	assign rf_we = rf_we_reg;
	assign branch = branch_reg;
	assign selpc = selpc_reg;
	assign zeropc = zeropc_reg;
	assign dmapc = dmapc_reg;
	assign pc_ce = pc_ce_reg;
	assign ret_ce = ret_ce_reg;

	// Internal logic for datapath module (Assumption based on typical datapath in a CPU)
	reg [N:0]  addr_nxt_reg;
	reg [N:0]  res_reg;
	
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			addr_nxt_reg <= 0;
			res_reg <= 0;
		end else if (rdy) begin
			// Example simplified datapath logic
			addr_nxt_reg <= insn[N:0];
			res_reg <= {N{1'b0}}; // Dummy logic
		end
	end
	
	assign addr_nxt = addr_nxt_reg;
	assign d = res_reg;

endmodule