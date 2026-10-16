module fft256_processor
 (
    input clk,
    input reset,
    input signed [15:0] xr_in,
    input signed [15:0] xi_in,
    output reg fft_valid,
    output reg signed [15:0] fftr,
    output reg signed [15:0] ffti,
    output [8:0] rcount_o,
    output [15:0] xr_out0,
    output [15:0] xi_out0,
    output [15:0] xr_out1,
    output [15:0] xi_out1,
    output [15:0] xr_out255,
    output [15:0] xi_out255,
    output [8:0] stage_o,
    output [8:0] gcount_o,
    output [8:0] i1_o,
    output [8:0] i2_o,
    output [8:0] k1_o,
    output [8:0] k2_o,
    output [8:0] w_o,
    output [8:0] dw_o,
    output reg [8:0] wo
 );

reg [2:0] s;
parameter start = 0, load = 1, calc = 2, update = 3, reverse = 4, done = 5;
reg [8:0] w;
reg signed [15:0] sin, cos;
reg signed [15:0] tr, ti;
reg signed [31:0] cos_tr, sin_ti, cos_ti, sin_tr;
reg [15:0] cos_rom[127:0];
reg [15:0] sin_rom[127:0];
reg [8:0] i1, i2, gcount, k1, k2;
reg [8:0] stage, dw;
reg [7:0] rcount;
reg [7:0] slv, rslv;
wire [8:0] N, ldN;

assign N = 256;
assign ldN = 8;

reg [15:0] xr[255:0];
reg [15:0] xi[255:0];

always @ (negedge clk or posedge reset) begin
    if (reset == 1) begin
        cos <= 0;
        sin <= 0;
    end else begin
        cos <= cos_rom[w[6:0]];
        sin <= sin_rom[w[6:0]];
    end
end

always @(posedge reset or posedge clk) begin : States
    integer k;
    reg [8:0] count;
    if (reset) begin
        s <= start;
        count = 0;
        gcount = 0;
        stage = 1;
        i1 = 0;
        i2 = N / 2;
        k1 = N;
        k2 = N / 2;
        dw = 1;
        fft_valid <= 0;
        fftr <= 0;
        ffti <= 0;
        wo <= 0;
    end else begin
        case (s)
            start: begin
                s <= load;
                count <= 0;
                w <= 0;
                gcount = 0;
                stage = 1;
                i1 = 0;
                i2 = N / 2;
                k1 = N;
                k2 = N / 2;
                dw = 1;
                fft_valid <= 0;
                rcount <= 0;
            end
            load: begin
                xr[count] <= xr_in;
                xi[count] <= xi_in;
                count <= count + 1;
                if (count == N) s <= calc;
            end
            calc: begin
                tr = xr[i1] - xr[i2];
                xr[i1] <= xr[i1] + xr[i2];
                ti = xi[i1] - xi[i2];
                xi[i1] <= xi[i1] + xi[i2];
                cos_tr = cos * tr;
                sin_ti = sin * ti;
                xr[i2] <= (cos_tr >>> 14) + (sin_ti >>> 14);
                cos_ti = cos * ti;
                sin_tr = sin * tr;
                xi[i2] <= (cos_ti >>> 14) - (sin_tr >>> 14);
                s <= update;
            end
            update: begin
                s <= calc;
                i1 = i1 + k1;
                i2 = i1 + k2;
                wo <= 1;
                if (i1 >= N-1) begin
                    gcount = gcount + 1;
                    i1 = gcount;
                    i2 = i1 + k2;
                    wo <= 2;
                    if (gcount >= k2) begin
                        gcount = 0;
                        i1 = 0;
                        i2 = k2;
                        dw = dw * 2;
                        stage = stage + 1;
                        wo <= 3;
                        if (stage > ldN) begin
                            s <= reverse;
                            count = 0;
                            wo <= 4;
                        end else begin
                            k1 = k2;
                            k2 = k2 / 2;
                            i1 = 0;
                            i2 = k2;
                            w <= 0;
                            wo <= 5;
                        end
                    end else begin
                        i1 = gcount;
                        i2 = i1 + k2;
                        w <= w + dw;
                        wo <= 6;
                    end
                end
            end
            reverse: begin
                fft_valid <= 1;
                for (k = 0; k <= 7; k = k + 1) begin
                    rcount[k] = count[7 - k];
                end
                fftr <= xr[rcount];
                ffti <= xi[rcount];
                count = count + 1;
                if (count >= N) s <= done;
            end
            done: begin
                s <= start;
            end
        endcase
    end
end

assign xr_out0 = xr[0];
assign xi_out0 = xi[0];
assign xr_out1 = xr[1];
assign xi_out1 = xi[1];
assign xr_out255 = xr[255];
assign xi_out255 = xi[255];
assign i1_o = i1;
assign i2_o = i2;
assign stage_o = stage;
assign gcount_o = gcount;
assign k1_o = k1;
assign k2_o = k2;
assign w_o = w;
assign dw_o = dw;
assign rcount_o = rcount;
endmodule