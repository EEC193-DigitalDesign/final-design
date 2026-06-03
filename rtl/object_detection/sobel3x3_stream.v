//=======================================================
// sobel3x3_stream.v
// Coordinate-driven Sobel L1 edge magnitude for sparse-valid
// 320x240 streams. Output coordinate is the 3x3 window center.
//=======================================================
module sobel3x3_stream #(
    parameter IMAGE_WIDTH = 320
)(
    input             clk,
    input             rst_n,
    input             pix_valid,
    input      [9:0]  x_in,
    input      [9:0]  y_in,
    input      [7:0]  pix_in,
    input      [12:0] edge_thresh_l1,

    output reg [7:0]  mag_out,
    output reg        mag_valid,
    output reg [9:0]  x_out,
    output reg [9:0]  y_out
);

    reg [7:0] line1 [0:IMAGE_WIDTH-1];
    reg [7:0] line2 [0:IMAGE_WIDTH-1];

    wire [7:0] line1_q = line1[x_in];
    wire [7:0] line2_q = line2[x_in];

    reg [7:0] w00, w01, w02;
    reg [7:0] w10, w11, w12;
    reg [7:0] w20, w21, w22;

    reg       win_valid_q;
    reg       win_edge_ok_q;
    reg [9:0] win_x_q;
    reg [9:0] win_y_q;

    wire signed [11:0] p00 = $signed({4'b0, w00});
    wire signed [11:0] p01 = $signed({4'b0, w01});
    wire signed [11:0] p02 = $signed({4'b0, w02});
    wire signed [11:0] p10 = $signed({4'b0, w10});
    wire signed [11:0] p12 = $signed({4'b0, w12});
    wire signed [11:0] p20 = $signed({4'b0, w20});
    wire signed [11:0] p21 = $signed({4'b0, w21});
    wire signed [11:0] p22 = $signed({4'b0, w22});

    wire signed [11:0] gx = -p00 + p02 - (p10 <<< 1) + (p12 <<< 1) - p20 + p22;
    wire signed [11:0] gy = -p00 - (p01 <<< 1) - p02 + p20 + (p21 <<< 1) + p22;

    wire [11:0] abs_gx = gx[11] ? (~gx + 12'd1) : gx;
    wire [11:0] abs_gy = gy[11] ? (~gy + 12'd1) : gy;
    wire [12:0] mag_l1 = {1'b0, abs_gx} + {1'b0, abs_gy};

    // Binary edge normalization for the matched filter:
    // once an edge is above the adjustable raw L1 Sobel threshold, output 255.
    wire [7:0] mag_binary = (mag_l1 >= edge_thresh_l1) ? 8'hFF : 8'd0;
    //wire [7:0] mag_clamped = (|mag_l1[12:8]) ? 8'hFF : mag_l1[7:0];

    wire current_edge_ok = pix_valid & (x_in >= 10'd2) & (y_in >= 10'd2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w00 <= 8'd0; w01 <= 8'd0; w02 <= 8'd0;
            w10 <= 8'd0; w11 <= 8'd0; w12 <= 8'd0;
            w20 <= 8'd0; w21 <= 8'd0; w22 <= 8'd0;
            win_valid_q <= 1'b0;
            win_edge_ok_q <= 1'b0;
            win_x_q     <= 10'd0;
            win_y_q     <= 10'd0;
            mag_out     <= 8'd0;
            mag_valid   <= 1'b0;
            x_out       <= 10'd0;
            y_out       <= 10'd0;
        end else begin
            mag_valid <= win_valid_q;
            x_out     <= win_x_q;
            y_out     <= win_y_q;
            mag_out   <= !win_edge_ok_q ? 8'd0 : mag_binary;

            if (pix_valid) begin
                line2[x_in] <= line1_q;
                line1[x_in] <= pix_in;

                if (x_in == 10'd0) begin
                    w00 <= 8'd0;    w01 <= 8'd0;    w02 <= line2_q;
                    w10 <= 8'd0;    w11 <= 8'd0;    w12 <= line1_q;
                    w20 <= 8'd0;    w21 <= 8'd0;    w22 <= pix_in;
                end else begin
                    w00 <= w01;     w01 <= w02;     w02 <= line2_q;
                    w10 <= w11;     w11 <= w12;     w12 <= line1_q;
                    w20 <= w21;     w21 <= w22;     w22 <= pix_in;
                end

                win_valid_q   <= 1'b1;
                win_edge_ok_q <= current_edge_ok;
                win_x_q <= x_in - 10'd1;
                win_y_q <= y_in - 10'd1;
            end else begin
                win_valid_q   <= 1'b0;
                win_edge_ok_q <= 1'b0;
            end
        end
    end

endmodule
