//=======================================================
// detection_logic.v
// Single-scale per-frame best-score tracker for the
// 320x240 sparse edge matched-filter stream.
//=======================================================
module detection_logic #(
    parameter SCORE_W       = 32,
    parameter TEMPLATE_SIZE = 64
)(
    input                       clk,
    input                       rst_n,

    input  signed [SCORE_W-1:0] score,
    input                       score_valid,
    input  [9:0]                x_score,   // template bottom-right X in 320-wide coords
    input  [9:0]                y_score,   // template bottom-right Y in 240-tall coords

    input                       vs,        // VGA_VS, active-low pulse
    input  signed [SCORE_W-1:0] threshold,

    output reg                  found,
    output reg [9:0]            det_x,     // top-left X in 320-wide coords
    output reg [9:0]            det_y,     // top-left Y in 240-tall coords
    output reg [SCORE_W-1:0]    confidence
);

    localparam [9:0] TEMPLATE_LAST = TEMPLATE_SIZE - 1;

    reg vs_d1, vs_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_d1 <= 1'b1;
            vs_d2 <= 1'b1;
        end else begin
            vs_d1 <= vs;
            vs_d2 <= vs_d1;
        end
    end
    wire frame_end = vs_d1 & ~vs_d2;

    reg signed [SCORE_W-1:0] best_score;
    reg [9:0]                best_x;
    reg [9:0]                best_y;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            best_score <= {1'b1, {(SCORE_W-1){1'b0}}};
            best_x     <= 10'd0;
            best_y     <= 10'd0;
            found      <= 1'b0;
            det_x      <= 10'd0;
            det_y      <= 10'd0;
            confidence <= {SCORE_W{1'b0}};
        end else if (frame_end) begin
            if (best_score > threshold) begin
                found      <= 1'b1;
                det_x      <= (best_x >= TEMPLATE_LAST) ? (best_x - TEMPLATE_LAST) : 10'd0;
                det_y      <= (best_y >= TEMPLATE_LAST) ? (best_y - TEMPLATE_LAST) : 10'd0;
                confidence <= best_score[SCORE_W-1] ? {SCORE_W{1'b0}} : best_score;
            end else begin
                found      <= 1'b0;
                confidence <= {SCORE_W{1'b0}};
            end

            best_score <= {1'b1, {(SCORE_W-1){1'b0}}};
            best_x     <= 10'd0;
            best_y     <= 10'd0;
        end else if (score_valid && (score > best_score)) begin
            best_score <= score;
            best_x     <= x_score;
            best_y     <= y_score;
        end
    end

endmodule
