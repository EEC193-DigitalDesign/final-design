// Auto-generated cow sparse edge template for rtl/object_detection/sparse_template_matcher.v
// Source image: objects/cow/cowSide.jpg
// Source SHA256: b07b473f22a7a8ae
// Generated: 2026-06-03T18:17:51+00:00
// Object: cow | Template: 64x64 | Num taps: 64 | Tap format: {row[5:0], col[5:0], signed weight[7:0]}
// Located in rtl/object_detection/templates/ and included by score_tree.v

assign tap_data[ 0] = {6'd33, 6'd42, 8'h07}; // row=33, col=42, w=+7 (pos)
assign tap_data[ 1] = {6'd35, 6'd48, 8'h07}; // row=35, col=48, w=+7 (pos)
assign tap_data[ 2] = {6'd38, 6'd46, 8'h07}; // row=38, col=46, w=+7 (pos)
assign tap_data[ 3] = {6'd37, 6'd43, 8'h07}; // row=37, col=43, w=+7 (pos)
assign tap_data[ 4] = {6'd40, 6'd43, 8'h07}; // row=40, col=43, w=+7 (pos)
assign tap_data[ 5] = {6'd43, 6'd44, 8'h07}; // row=43, col=44, w=+7 (pos)
assign tap_data[ 6] = {6'd41, 6'd40, 8'h07}; // row=41, col=40, w=+7 (pos)
assign tap_data[ 7] = {6'd44, 6'd41, 8'h07}; // row=44, col=41, w=+7 (pos)
assign tap_data[ 8] = {6'd47, 6'd40, 8'h07}; // row=47, col=40, w=+7 (pos)
assign tap_data[ 9] = {6'd53, 6'd42, 8'h07}; // row=53, col=42, w=+7 (pos)
assign tap_data[10] = {6'd48, 6'd37, 8'h07}; // row=48, col=37, w=+7 (pos)
assign tap_data[11] = {6'd56, 6'd36, 8'h07}; // row=56, col=36, w=+7 (pos)
assign tap_data[12] = {6'd48, 6'd34, 8'h07}; // row=48, col=34, w=+7 (pos)
assign tap_data[13] = {6'd47, 6'd31, 8'h07}; // row=47, col=31, w=+7 (pos)
assign tap_data[14] = {6'd42, 6'd31, 8'h07}; // row=42, col=31, w=+7 (pos)
assign tap_data[15] = {6'd45, 6'd28, 8'h07}; // row=45, col=28, w=+7 (pos)
assign tap_data[16] = {6'd42, 6'd28, 8'h07}; // row=42, col=28, w=+7 (pos)
assign tap_data[17] = {6'd44, 6'd25, 8'h07}; // row=44, col=25, w=+7 (pos)
assign tap_data[18] = {6'd45, 6'd22, 8'h07}; // row=45, col=22, w=+7 (pos)
assign tap_data[19] = {6'd46, 6'd18, 8'h07}; // row=46, col=18, w=+7 (pos)
assign tap_data[20] = {6'd46, 6'd15, 8'h07}; // row=46, col=15, w=+7 (pos)
assign tap_data[21] = {6'd45, 6'd12, 8'h07}; // row=45, col=12, w=+7 (pos)
assign tap_data[22] = {6'd41, 6'd12, 8'h07}; // row=41, col=12, w=+7 (pos)
assign tap_data[23] = {6'd38, 6'd13, 8'h07}; // row=38, col=13, w=+7 (pos)
assign tap_data[24] = {6'd36, 6'd9 , 8'h07}; // row=36, col=9, w=+7 (pos)
assign tap_data[25] = {6'd33, 6'd5 , 8'h07}; // row=33, col=5, w=+7 (pos)
assign tap_data[26] = {6'd31, 6'd8 , 8'h07}; // row=31, col=8, w=+7 (pos)
assign tap_data[27] = {6'd30, 6'd19, 8'h07}; // row=30, col=19, w=+7 (pos)
assign tap_data[28] = {6'd29, 6'd22, 8'h07}; // row=29, col=22, w=+7 (pos)
assign tap_data[29] = {6'd26, 6'd18, 8'h07}; // row=26, col=18, w=+7 (pos)
assign tap_data[30] = {6'd25, 6'd21, 8'h07}; // row=25, col=21, w=+7 (pos)
assign tap_data[31] = {6'd26, 6'd24, 8'h07}; // row=26, col=24, w=+7 (pos)
assign tap_data[32] = {6'd27, 6'd27, 8'h07}; // row=27, col=27, w=+7 (pos)
assign tap_data[33] = {6'd27, 6'd30, 8'h07}; // row=27, col=30, w=+7 (pos)
assign tap_data[34] = {6'd24, 6'd30, 8'h07}; // row=24, col=30, w=+7 (pos)
assign tap_data[35] = {6'd17, 6'd32, 8'h07}; // row=17, col=32, w=+7 (pos)
assign tap_data[36] = {6'd4 , 6'd36, 8'h07}; // row=4, col=36, w=+7 (pos)
assign tap_data[37] = {6'd2 , 6'd39, 8'h07}; // row=2, col=39, w=+7 (pos)
assign tap_data[38] = {6'd1 , 6'd42, 8'h07}; // row=1, col=42, w=+7 (pos)
assign tap_data[39] = {6'd1 , 6'd45, 8'h07}; // row=1, col=45, w=+7 (pos)
assign tap_data[40] = {6'd3 , 6'd49, 8'h07}; // row=3, col=49, w=+7 (pos)
assign tap_data[41] = {6'd4 , 6'd53, 8'h07}; // row=4, col=53, w=+7 (pos)
assign tap_data[42] = {6'd8 , 6'd55, 8'h07}; // row=8, col=55, w=+7 (pos)
assign tap_data[43] = {6'd11, 6'd58, 8'h07}; // row=11, col=58, w=+7 (pos)
assign tap_data[44] = {6'd17, 6'd56, 8'h07}; // row=17, col=56, w=+7 (pos)
assign tap_data[45] = {6'd30, 6'd39, 8'h07}; // row=30, col=39, w=+7 (pos)
assign tap_data[46] = {6'd24, 6'd59, 8'h07}; // row=24, col=59, w=+7 (pos)
assign tap_data[47] = {6'd27, 6'd58, 8'h07}; // row=27, col=58, w=+7 (pos)
assign tap_data[48] = {6'd30, 6'd57, 8'h07}; // row=30, col=57, w=+7 (pos)
assign tap_data[49] = {6'd61, 6'd18, 8'h07}; // row=61, col=18, w=+7 (pos)
assign tap_data[50] = {6'd61, 6'd15, 8'h07}; // row=61, col=15, w=+7 (pos)
assign tap_data[51] = {6'd4 , 6'd44, 8'h07}; // row=4, col=44, w=+7 (pos)
assign tap_data[52] = {6'd9 , 6'd63, 8'hFE}; // row=9, col=63, w=-2 (neg)
assign tap_data[53] = {6'd11, 6'd0 , 8'hFE}; // row=11, col=0, w=-2 (neg)
assign tap_data[54] = {6'd47, 6'd52, 8'hFE}; // row=47, col=52, w=-2 (neg)
assign tap_data[55] = {6'd63, 6'd52, 8'hFE}; // row=63, col=52, w=-2 (neg)
assign tap_data[56] = {6'd55, 6'd63, 8'hFE}; // row=55, col=63, w=-2 (neg)
assign tap_data[57] = {6'd8 , 6'd14, 8'hFE}; // row=8, col=14, w=-2 (neg)
assign tap_data[58] = {6'd63, 6'd23, 8'hFE}; // row=63, col=23, w=-2 (neg)
assign tap_data[59] = {6'd11, 6'd8 , 8'hFE}; // row=11, col=8, w=-2 (neg)
assign tap_data[60] = {6'd62, 6'd62, 8'hFE}; // row=62, col=62, w=-2 (neg)
assign tap_data[61] = {6'd41, 6'd52, 8'hFE}; // row=41, col=52, w=-2 (neg)
assign tap_data[62] = {6'd44, 6'd62, 8'hFE}; // row=44, col=62, w=-2 (neg)
assign tap_data[63] = {6'd57, 6'd49, 8'hFE}; // row=57, col=49, w=-2 (neg)

function [5:0] cow_tap_row;
    input integer idx;
    begin
        case (idx)
              0: cow_tap_row = 6'd33;
              1: cow_tap_row = 6'd35;
              2: cow_tap_row = 6'd38;
              3: cow_tap_row = 6'd37;
              4: cow_tap_row = 6'd40;
              5: cow_tap_row = 6'd43;
              6: cow_tap_row = 6'd41;
              7: cow_tap_row = 6'd44;
              8: cow_tap_row = 6'd47;
              9: cow_tap_row = 6'd53;
             10: cow_tap_row = 6'd48;
             11: cow_tap_row = 6'd56;
             12: cow_tap_row = 6'd48;
             13: cow_tap_row = 6'd47;
             14: cow_tap_row = 6'd42;
             15: cow_tap_row = 6'd45;
             16: cow_tap_row = 6'd42;
             17: cow_tap_row = 6'd44;
             18: cow_tap_row = 6'd45;
             19: cow_tap_row = 6'd46;
             20: cow_tap_row = 6'd46;
             21: cow_tap_row = 6'd45;
             22: cow_tap_row = 6'd41;
             23: cow_tap_row = 6'd38;
             24: cow_tap_row = 6'd36;
             25: cow_tap_row = 6'd33;
             26: cow_tap_row = 6'd31;
             27: cow_tap_row = 6'd30;
             28: cow_tap_row = 6'd29;
             29: cow_tap_row = 6'd26;
             30: cow_tap_row = 6'd25;
             31: cow_tap_row = 6'd26;
             32: cow_tap_row = 6'd27;
             33: cow_tap_row = 6'd27;
             34: cow_tap_row = 6'd24;
             35: cow_tap_row = 6'd17;
             36: cow_tap_row = 6'd4;
             37: cow_tap_row = 6'd2;
             38: cow_tap_row = 6'd1;
             39: cow_tap_row = 6'd1;
             40: cow_tap_row = 6'd3;
             41: cow_tap_row = 6'd4;
             42: cow_tap_row = 6'd8;
             43: cow_tap_row = 6'd11;
             44: cow_tap_row = 6'd17;
             45: cow_tap_row = 6'd30;
             46: cow_tap_row = 6'd24;
             47: cow_tap_row = 6'd27;
             48: cow_tap_row = 6'd30;
             49: cow_tap_row = 6'd61;
             50: cow_tap_row = 6'd61;
             51: cow_tap_row = 6'd4;
             52: cow_tap_row = 6'd9;
             53: cow_tap_row = 6'd11;
             54: cow_tap_row = 6'd47;
             55: cow_tap_row = 6'd63;
             56: cow_tap_row = 6'd55;
             57: cow_tap_row = 6'd8;
             58: cow_tap_row = 6'd63;
             59: cow_tap_row = 6'd11;
             60: cow_tap_row = 6'd62;
             61: cow_tap_row = 6'd41;
             62: cow_tap_row = 6'd44;
             63: cow_tap_row = 6'd57;
            default: cow_tap_row = 6'd0;
        endcase
    end
endfunction

function [5:0] cow_tap_col;
    input integer idx;
    begin
        case (idx)
              0: cow_tap_col = 6'd42;
              1: cow_tap_col = 6'd48;
              2: cow_tap_col = 6'd46;
              3: cow_tap_col = 6'd43;
              4: cow_tap_col = 6'd43;
              5: cow_tap_col = 6'd44;
              6: cow_tap_col = 6'd40;
              7: cow_tap_col = 6'd41;
              8: cow_tap_col = 6'd40;
              9: cow_tap_col = 6'd42;
             10: cow_tap_col = 6'd37;
             11: cow_tap_col = 6'd36;
             12: cow_tap_col = 6'd34;
             13: cow_tap_col = 6'd31;
             14: cow_tap_col = 6'd31;
             15: cow_tap_col = 6'd28;
             16: cow_tap_col = 6'd28;
             17: cow_tap_col = 6'd25;
             18: cow_tap_col = 6'd22;
             19: cow_tap_col = 6'd18;
             20: cow_tap_col = 6'd15;
             21: cow_tap_col = 6'd12;
             22: cow_tap_col = 6'd12;
             23: cow_tap_col = 6'd13;
             24: cow_tap_col = 6'd9;
             25: cow_tap_col = 6'd5;
             26: cow_tap_col = 6'd8;
             27: cow_tap_col = 6'd19;
             28: cow_tap_col = 6'd22;
             29: cow_tap_col = 6'd18;
             30: cow_tap_col = 6'd21;
             31: cow_tap_col = 6'd24;
             32: cow_tap_col = 6'd27;
             33: cow_tap_col = 6'd30;
             34: cow_tap_col = 6'd30;
             35: cow_tap_col = 6'd32;
             36: cow_tap_col = 6'd36;
             37: cow_tap_col = 6'd39;
             38: cow_tap_col = 6'd42;
             39: cow_tap_col = 6'd45;
             40: cow_tap_col = 6'd49;
             41: cow_tap_col = 6'd53;
             42: cow_tap_col = 6'd55;
             43: cow_tap_col = 6'd58;
             44: cow_tap_col = 6'd56;
             45: cow_tap_col = 6'd39;
             46: cow_tap_col = 6'd59;
             47: cow_tap_col = 6'd58;
             48: cow_tap_col = 6'd57;
             49: cow_tap_col = 6'd18;
             50: cow_tap_col = 6'd15;
             51: cow_tap_col = 6'd44;
             52: cow_tap_col = 6'd63;
             53: cow_tap_col = 6'd0;
             54: cow_tap_col = 6'd52;
             55: cow_tap_col = 6'd52;
             56: cow_tap_col = 6'd63;
             57: cow_tap_col = 6'd14;
             58: cow_tap_col = 6'd23;
             59: cow_tap_col = 6'd8;
             60: cow_tap_col = 6'd62;
             61: cow_tap_col = 6'd52;
             62: cow_tap_col = 6'd62;
             63: cow_tap_col = 6'd49;
            default: cow_tap_col = 6'd0;
        endcase
    end
endfunction

function signed [7:0] cow_tap_weight;
    input integer idx;
    begin
        case (idx)
              0: cow_tap_weight = 8'sd7;
              1: cow_tap_weight = 8'sd7;
              2: cow_tap_weight = 8'sd7;
              3: cow_tap_weight = 8'sd7;
              4: cow_tap_weight = 8'sd7;
              5: cow_tap_weight = 8'sd7;
              6: cow_tap_weight = 8'sd7;
              7: cow_tap_weight = 8'sd7;
              8: cow_tap_weight = 8'sd7;
              9: cow_tap_weight = 8'sd7;
             10: cow_tap_weight = 8'sd7;
             11: cow_tap_weight = 8'sd7;
             12: cow_tap_weight = 8'sd7;
             13: cow_tap_weight = 8'sd7;
             14: cow_tap_weight = 8'sd7;
             15: cow_tap_weight = 8'sd7;
             16: cow_tap_weight = 8'sd7;
             17: cow_tap_weight = 8'sd7;
             18: cow_tap_weight = 8'sd7;
             19: cow_tap_weight = 8'sd7;
             20: cow_tap_weight = 8'sd7;
             21: cow_tap_weight = 8'sd7;
             22: cow_tap_weight = 8'sd7;
             23: cow_tap_weight = 8'sd7;
             24: cow_tap_weight = 8'sd7;
             25: cow_tap_weight = 8'sd7;
             26: cow_tap_weight = 8'sd7;
             27: cow_tap_weight = 8'sd7;
             28: cow_tap_weight = 8'sd7;
             29: cow_tap_weight = 8'sd7;
             30: cow_tap_weight = 8'sd7;
             31: cow_tap_weight = 8'sd7;
             32: cow_tap_weight = 8'sd7;
             33: cow_tap_weight = 8'sd7;
             34: cow_tap_weight = 8'sd7;
             35: cow_tap_weight = 8'sd7;
             36: cow_tap_weight = 8'sd7;
             37: cow_tap_weight = 8'sd7;
             38: cow_tap_weight = 8'sd7;
             39: cow_tap_weight = 8'sd7;
             40: cow_tap_weight = 8'sd7;
             41: cow_tap_weight = 8'sd7;
             42: cow_tap_weight = 8'sd7;
             43: cow_tap_weight = 8'sd7;
             44: cow_tap_weight = 8'sd7;
             45: cow_tap_weight = 8'sd7;
             46: cow_tap_weight = 8'sd7;
             47: cow_tap_weight = 8'sd7;
             48: cow_tap_weight = 8'sd7;
             49: cow_tap_weight = 8'sd7;
             50: cow_tap_weight = 8'sd7;
             51: cow_tap_weight = 8'sd7;
             52: cow_tap_weight = -8'sd2;
             53: cow_tap_weight = -8'sd2;
             54: cow_tap_weight = -8'sd2;
             55: cow_tap_weight = -8'sd2;
             56: cow_tap_weight = -8'sd2;
             57: cow_tap_weight = -8'sd2;
             58: cow_tap_weight = -8'sd2;
             59: cow_tap_weight = -8'sd2;
             60: cow_tap_weight = -8'sd2;
             61: cow_tap_weight = -8'sd2;
             62: cow_tap_weight = -8'sd2;
             63: cow_tap_weight = -8'sd2;
            default: cow_tap_weight = 8'sd0;
        endcase
    end
endfunction
