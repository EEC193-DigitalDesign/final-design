// Auto-generated 32x32 donut sparse edge template
// Source image: donut.png
// Source SHA256: c40e03eae30d5a32
// Generated: 2026-06-02T20:56:14+00:00
// Template: 32x32 | Num taps: 32 | Tap format: {row[4:0], col[4:0], signed weight[7:0]}

assign tap_data[ 0] = {5'd16, 5'd29, 8'h07}; // row=16, col=29, w=+7 (pos)
assign tap_data[ 1] = {5'd21, 5'd28, 8'h07}; // row=21, col=28, w=+7 (pos)
assign tap_data[ 2] = {5'd25, 5'd25, 8'h07}; // row=25, col=25, w=+7 (pos)
assign tap_data[ 3] = {5'd29, 5'd16, 8'h07}; // row=29, col=16, w=+7 (pos)
assign tap_data[ 4] = {5'd28, 5'd11, 8'h07}; // row=28, col=11, w=+7 (pos)
assign tap_data[ 5] = {5'd25, 5'd6 , 8'h07}; // row=25, col=6, w=+7 (pos)
assign tap_data[ 6] = {5'd21, 5'd3 , 8'h07}; // row=21, col=3, w=+7 (pos)
assign tap_data[ 7] = {5'd16, 5'd1 , 8'h07}; // row=16, col=1, w=+7 (pos)
assign tap_data[ 8] = {5'd10, 5'd2 , 8'h07}; // row=10, col=2, w=+7 (pos)
assign tap_data[ 9] = {5'd6 , 5'd5 , 8'h07}; // row=6, col=5, w=+7 (pos)
assign tap_data[10] = {5'd4 , 5'd8 , 8'h07}; // row=4, col=8, w=+7 (pos)
assign tap_data[11] = {5'd2 , 5'd11, 8'h07}; // row=2, col=11, w=+7 (pos)
assign tap_data[12] = {5'd1 , 5'd16, 8'h07}; // row=1, col=16, w=+7 (pos)
assign tap_data[13] = {5'd3 , 5'd22, 8'h07}; // row=3, col=22, w=+7 (pos)
assign tap_data[14] = {5'd5 , 5'd26, 8'h07}; // row=5, col=26, w=+7 (pos)
assign tap_data[15] = {5'd10, 5'd29, 8'h07}; // row=10, col=29, w=+7 (pos)
assign tap_data[16] = {5'd16, 5'd19, 8'h07}; // row=16, col=19, w=+7 (pos)
assign tap_data[17] = {5'd19, 5'd17, 8'h07}; // row=19, col=17, w=+7 (pos)
assign tap_data[18] = {5'd19, 5'd15, 8'h07}; // row=19, col=15, w=+7 (pos)
assign tap_data[19] = {5'd18, 5'd13, 8'h07}; // row=18, col=13, w=+7 (pos)
assign tap_data[20] = {5'd16, 5'd11, 8'h07}; // row=16, col=11, w=+7 (pos)
assign tap_data[21] = {5'd12, 5'd6 , 8'h07}; // row=12, col=6, w=+7 (pos)
assign tap_data[22] = {5'd9 , 5'd8 , 8'h07}; // row=9, col=8, w=+7 (pos)
assign tap_data[23] = {5'd12, 5'd15, 8'h07}; // row=12, col=15, w=+7 (pos)
assign tap_data[24] = {5'd13, 5'd18, 8'h07}; // row=13, col=18, w=+7 (pos)
assign tap_data[25] = {5'd14, 5'd20, 8'h07}; // row=14, col=20, w=+7 (pos)
assign tap_data[26] = {5'd0 , 5'd25, 8'hFE}; // row=0, col=25, w=-2 (neg)
assign tap_data[27] = {5'd29, 5'd3 , 8'hFE}; // row=29, col=3, w=-2 (neg)
assign tap_data[28] = {5'd5 , 5'd1 , 8'hFE}; // row=5, col=1, w=-2 (neg)
assign tap_data[29] = {5'd0 , 5'd6 , 8'hFE}; // row=0, col=6, w=-2 (neg)
assign tap_data[30] = {5'd26, 5'd0 , 8'hFE}; // row=26, col=0, w=-2 (neg)
assign tap_data[31] = {5'd30, 5'd27, 8'hFE}; // row=30, col=27, w=-2 (neg)

function [4:0] donut_tap_row;
    input integer idx;
    begin
        case (idx)
              0: donut_tap_row = 5'd16;
              1: donut_tap_row = 5'd21;
              2: donut_tap_row = 5'd25;
              3: donut_tap_row = 5'd29;
              4: donut_tap_row = 5'd28;
              5: donut_tap_row = 5'd25;
              6: donut_tap_row = 5'd21;
              7: donut_tap_row = 5'd16;
              8: donut_tap_row = 5'd10;
              9: donut_tap_row = 5'd6;
             10: donut_tap_row = 5'd4;
             11: donut_tap_row = 5'd2;
             12: donut_tap_row = 5'd1;
             13: donut_tap_row = 5'd3;
             14: donut_tap_row = 5'd5;
             15: donut_tap_row = 5'd10;
             16: donut_tap_row = 5'd16;
             17: donut_tap_row = 5'd19;
             18: donut_tap_row = 5'd19;
             19: donut_tap_row = 5'd18;
             20: donut_tap_row = 5'd16;
             21: donut_tap_row = 5'd12;
             22: donut_tap_row = 5'd9;
             23: donut_tap_row = 5'd12;
             24: donut_tap_row = 5'd13;
             25: donut_tap_row = 5'd14;
             26: donut_tap_row = 5'd0;
             27: donut_tap_row = 5'd29;
             28: donut_tap_row = 5'd5;
             29: donut_tap_row = 5'd0;
             30: donut_tap_row = 5'd26;
             31: donut_tap_row = 5'd30;
            default: donut_tap_row = 5'd0;
        endcase
    end
endfunction

function [4:0] donut_tap_col;
    input integer idx;
    begin
        case (idx)
              0: donut_tap_col = 5'd29;
              1: donut_tap_col = 5'd28;
              2: donut_tap_col = 5'd25;
              3: donut_tap_col = 5'd16;
              4: donut_tap_col = 5'd11;
              5: donut_tap_col = 5'd6;
              6: donut_tap_col = 5'd3;
              7: donut_tap_col = 5'd1;
              8: donut_tap_col = 5'd2;
              9: donut_tap_col = 5'd5;
             10: donut_tap_col = 5'd8;
             11: donut_tap_col = 5'd11;
             12: donut_tap_col = 5'd16;
             13: donut_tap_col = 5'd22;
             14: donut_tap_col = 5'd26;
             15: donut_tap_col = 5'd29;
             16: donut_tap_col = 5'd19;
             17: donut_tap_col = 5'd17;
             18: donut_tap_col = 5'd15;
             19: donut_tap_col = 5'd13;
             20: donut_tap_col = 5'd11;
             21: donut_tap_col = 5'd6;
             22: donut_tap_col = 5'd8;
             23: donut_tap_col = 5'd15;
             24: donut_tap_col = 5'd18;
             25: donut_tap_col = 5'd20;
             26: donut_tap_col = 5'd25;
             27: donut_tap_col = 5'd3;
             28: donut_tap_col = 5'd1;
             29: donut_tap_col = 5'd6;
             30: donut_tap_col = 5'd0;
             31: donut_tap_col = 5'd27;
            default: donut_tap_col = 5'd0;
        endcase
    end
endfunction

function signed [7:0] donut_tap_weight;
    input integer idx;
    begin
        case (idx)
              0: donut_tap_weight = 8'sd7;
              1: donut_tap_weight = 8'sd7;
              2: donut_tap_weight = 8'sd7;
              3: donut_tap_weight = 8'sd7;
              4: donut_tap_weight = 8'sd7;
              5: donut_tap_weight = 8'sd7;
              6: donut_tap_weight = 8'sd7;
              7: donut_tap_weight = 8'sd7;
              8: donut_tap_weight = 8'sd7;
              9: donut_tap_weight = 8'sd7;
             10: donut_tap_weight = 8'sd7;
             11: donut_tap_weight = 8'sd7;
             12: donut_tap_weight = 8'sd7;
             13: donut_tap_weight = 8'sd7;
             14: donut_tap_weight = 8'sd7;
             15: donut_tap_weight = 8'sd7;
             16: donut_tap_weight = 8'sd7;
             17: donut_tap_weight = 8'sd7;
             18: donut_tap_weight = 8'sd7;
             19: donut_tap_weight = 8'sd7;
             20: donut_tap_weight = 8'sd7;
             21: donut_tap_weight = 8'sd7;
             22: donut_tap_weight = 8'sd7;
             23: donut_tap_weight = 8'sd7;
             24: donut_tap_weight = 8'sd7;
             25: donut_tap_weight = 8'sd7;
             26: donut_tap_weight = -8'sd2;
             27: donut_tap_weight = -8'sd2;
             28: donut_tap_weight = -8'sd2;
             29: donut_tap_weight = -8'sd2;
             30: donut_tap_weight = -8'sd2;
             31: donut_tap_weight = -8'sd2;
            default: donut_tap_weight = 8'sd0;
        endcase
    end
endfunction
