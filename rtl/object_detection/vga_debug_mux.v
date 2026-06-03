//=======================================================
// vga_debug_mux.v
// Debug display for the downsampled Sobel matched-filter
// pipeline, with the 320x240 detection box scaled to VGA.
//
// Modes:
//   00: Camera RGB, or grayscale when gray_view=1
//   01: Sobel edge magnitude
//   10: Signed matched-filter score heatmap with frame auto-contrast
//       positive score: black -> red -> yellow -> white
//       negative score: black -> blue -> cyan -> white
//   11: Score threshold mask
//
// Heatmap note:
//   The matcher score stream is not synchronized to the current VGA pixel.
//   This mux stores each incoming score at its score_x/score_y coordinate in a
//   320x240 RAM, then reads that RAM during VGA scanout.  The RAM stores only
//   display data, not the full 32-bit score: {threshold_mask, sign, magnitude}.
//
// Auto-contrast note:
//   True score/max division would be expensive.  Instead the mux measures the
//   maximum absolute score during one frame and converts it to a power-of-two
//   display shift for the next frame.  This keeps the heatmap readable while
//   using shifts, compares, and one small score RAM instead of a divider.
//
// Quartus RAM-inference fix:
//   The heatmap RAM is isolated in a simple synchronous dual-port leaf module.
//   Keeping memory accesses outside the async-reset control block prevents
//   Quartus from treating the 76,800 x 10 array as registers.
//=======================================================

module vga_heatmap_sdp_ram #(
    parameter DATA_W = 10,
    parameter ADDR_W = 17,
    parameter DEPTH  = 76800
)(
    input                   clk,
    input                   wr_en,
    input      [ADDR_W-1:0] wr_addr,
    input      [DATA_W-1:0] wr_data,
    input                   rd_en,
    input      [ADDR_W-1:0] rd_addr,
    output reg [DATA_W-1:0] rd_data
);
    (* ramstyle = "M10K, no_rw_check" *) reg [DATA_W-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
        if (rd_en)
            rd_data <= mem[rd_addr];
    end
endmodule

module vga_debug_mux #(
    parameter SCORE_W          = 32,
    parameter BOX_SIZE_DS      = 64,
    parameter BOX_THICK        = 2,
    parameter DS_WIDTH         = 320,
    parameter DS_HEIGHT        = 240,
    parameter VGA_WIDTH        = 640,
    parameter VGA_HEIGHT       = 480,
    parameter SCORE_SHIFT      = 9,
    parameter AUTOCONTRAST_EN  = 0
)(
    input                       clk,
    input                       rst_n,

    input      [1:0]            mode,
    input                       overlay_en,
    input                       gray_view,

    input      [7:0]            cam_r,
    input      [7:0]            cam_g,
    input      [7:0]            cam_b,

    input      [7:0]            gray,
    input                       gray_valid,
    input      [7:0]            edge_mag,
    input                       edge_valid,

    input  signed [SCORE_W-1:0] score,
    input                       score_valid,
    input      [9:0]            score_x,
    input      [9:0]            score_y,
    input  signed [SCORE_W-1:0] threshold,

    input                       found,
    input      [9:0]            det_x_ds,
    input      [9:0]            det_y_ds,

    input      [9:0]            pixel_x,
    input      [9:0]            pixel_y,
    input                       blank_n,
    input                       frame_sync,

    output reg [7:0]            vga_r,
    output reg [7:0]            vga_g,
    output reg [7:0]            vga_b
);

    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            for (clog2 = 0; v > 0; clog2 = clog2 + 1)
                v = v >> 1;
        end
    endfunction

    localparam HEATMAP_PIXELS = DS_WIDTH * DS_HEIGHT;
    localparam HEATMAP_ADDR_W = clog2(HEATMAP_PIXELS);

    reg [7:0] gray_hold;
    reg [7:0] edge_hold;
    reg signed [SCORE_W-1:0] score_hold;

    reg frame_sync_d;
    reg [4:0] display_shift;
    reg [SCORE_W-1:0] current_frame_abs_max;
    reg [SCORE_W-1:0] last_frame_abs_max;

    wire frame_start = frame_sync_d & ~frame_sync;

    function [SCORE_W-1:0] abs_score;
        input signed [SCORE_W-1:0] s;
        begin
            if (s[SCORE_W-1])
                abs_score = (~s[SCORE_W-1:0]) + {{(SCORE_W-1){1'b0}}, 1'b1};
            else
                abs_score = s[SCORE_W-1:0];
        end
    endfunction

    function [4:0] max_to_shift;
        input [SCORE_W-1:0] max_abs;
        integer bit_idx;
        begin
            max_to_shift = 5'd0;
            for (bit_idx = 0; bit_idx < SCORE_W; bit_idx = bit_idx + 1) begin
                if (max_abs[bit_idx]) begin
                    if (bit_idx > 7)
                        max_to_shift = bit_idx - 7;
                    else
                        max_to_shift = 5'd0;
                end
            end
        end
    endfunction

    function [7:0] sat_shift_to_u8;
        input [SCORE_W-1:0] value;
        input [4:0] shift;
        reg [SCORE_W-1:0] scaled;
        begin
            scaled = value >> shift;
            if (scaled > {{(SCORE_W-8){1'b0}}, 8'd255})
                sat_shift_to_u8 = 8'd255;
            else
                sat_shift_to_u8 = scaled[7:0];
        end
    endfunction

    function [8:0] score_to_signed_heat;
        input signed [SCORE_W-1:0] s;
        input [4:0] shift;
        reg [SCORE_W-1:0] s_abs;
        begin
            s_abs = abs_score(s);
            score_to_signed_heat = {s[SCORE_W-1], sat_shift_to_u8(s_abs, shift)};
        end
    endfunction

    function [7:0] scale3_sat;
        input [7:0] value;
        reg [9:0] scaled;
        begin
            scaled = {2'b00, value} + {1'b0, value, 1'b0};
            scale3_sat = (scaled > 10'd255) ? 8'd255 : scaled[7:0];
        end
    endfunction

    function [23:0] signed_heat_to_rgb;
        input       neg;
        input [7:0] mag;
        reg [7:0] r;
        reg [7:0] g;
        reg [7:0] b;
        begin
            r = 8'd0;
            g = 8'd0;
            b = 8'd0;

            if (mag == 8'd0) begin
                r = 8'd0;
                g = 8'd0;
                b = 8'd0;
            end else if (!neg) begin
                // Positive match: black -> red -> yellow -> white.
                if (mag < 8'd85) begin
                    r = scale3_sat(mag);
                    g = 8'd0;
                    b = 8'd0;
                end else if (mag < 8'd170) begin
                    r = 8'd255;
                    g = scale3_sat(mag - 8'd85);
                    b = 8'd0;
                end else begin
                    r = 8'd255;
                    g = 8'd255;
                    b = scale3_sat(mag - 8'd170);
                end
            end else begin
                // Negative anti-match: black -> blue -> cyan -> white.
                if (mag < 8'd85) begin
                    r = 8'd0;
                    g = 8'd0;
                    b = scale3_sat(mag);
                end else if (mag < 8'd170) begin
                    r = 8'd0;
                    g = scale3_sat(mag - 8'd85);
                    b = 8'd255;
                end else begin
                    r = scale3_sat(mag - 8'd170);
                    g = 8'd255;
                    b = 8'd255;
                end
            end
            signed_heat_to_rgb = {r, g, b};
        end
    endfunction

    wire score_wr_in_range = (score_x < DS_WIDTH) && (score_y < DS_HEIGHT);
    wire [HEATMAP_ADDR_W-1:0] score_wr_addr = (score_y * DS_WIDTH) + score_x;
    wire [8:0] signed_heat_wr = score_to_signed_heat(score, display_shift);
    wire       score_mask_wr = (score > threshold);
    wire [9:0] heatmap_wr_data = {score_mask_wr, signed_heat_wr};
    wire [SCORE_W-1:0] score_abs_now = abs_score(score);

    // The VGA frame is exactly 2x the downsampled detector frame in this
    // project, so each 2x2 VGA block reads one downsampled score cell.
    // The RAM has a registered read port, so address the next active pixel;
    // the data returned on this clock is then aligned with the current pixel.
    wire at_last_active_x = (pixel_x == (VGA_WIDTH - 1));
    wire at_last_active_y = (pixel_y == (VGA_HEIGHT - 1));
    wire [10:0] heat_next_vga_x = at_last_active_x ? 11'd0 : ({1'b0, pixel_x} + 11'd1);
    wire [10:0] heat_next_vga_y = at_last_active_x ?
                                   (at_last_active_y ? 11'd0 : ({1'b0, pixel_y} + 11'd1)) :
                                   {1'b0, pixel_y};
    wire [9:0] heat_rd_x = heat_next_vga_x[10:1];
    wire [9:0] heat_rd_y = heat_next_vga_y[10:1];
    wire       heat_rd_in_range = (heat_rd_x < DS_WIDTH) && (heat_rd_y < DS_HEIGHT);
    wire [HEATMAP_ADDR_W-1:0] heat_rd_addr = (heat_rd_y * DS_WIDTH) + heat_rd_x;

    wire [9:0] heatmap_ram_q;
    reg        heat_rd_in_range_q;
    wire [9:0] heatmap_rd_data = heat_rd_in_range_q ? heatmap_ram_q : 10'd0;

    vga_heatmap_sdp_ram #(
        .DATA_W (10),
        .ADDR_W (HEATMAP_ADDR_W),
        .DEPTH  (HEATMAP_PIXELS)
    ) u_heatmap_ram (
        .clk     (clk),
        .wr_en   (score_valid && score_wr_in_range),
        .wr_addr (score_wr_addr),
        .wr_data (heatmap_wr_data),
        .rd_en   (heat_rd_in_range),
        .rd_addr (heat_rd_addr),
        .rd_data (heatmap_ram_q)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray_hold             <= 8'd0;
            edge_hold             <= 8'd0;
            score_hold            <= {SCORE_W{1'b0}};
            heat_rd_in_range_q    <= 1'b0;
            frame_sync_d          <= 1'b1;
            display_shift         <= SCORE_SHIFT;
            current_frame_abs_max <= {SCORE_W{1'b0}};
            last_frame_abs_max    <= {SCORE_W{1'b0}};
        end else begin
            frame_sync_d <= frame_sync;
            heat_rd_in_range_q <= heat_rd_in_range;

            if (frame_start) begin
                last_frame_abs_max    <= current_frame_abs_max;
                current_frame_abs_max <= {SCORE_W{1'b0}};
                if (AUTOCONTRAST_EN && (current_frame_abs_max != {SCORE_W{1'b0}}))
                    display_shift <= max_to_shift(current_frame_abs_max);
                else if (!AUTOCONTRAST_EN)
                    display_shift <= SCORE_SHIFT;
            end else if (score_valid && (score_abs_now > current_frame_abs_max)) begin
                current_frame_abs_max <= score_abs_now;
            end

            if (gray_valid)
                gray_hold <= gray;
            if (edge_valid)
                edge_hold <= edge_mag;
            if (score_valid)
                score_hold <= score;
        end
    end

    wire [7:0] heat_mag = heatmap_rd_data[7:0];
    wire       heat_neg = heatmap_rd_data[8];
    wire       mask_val = heatmap_rd_data[9];
    wire [23:0] heat_rgb = signed_heat_to_rgb(heat_neg, heat_mag);

    wire heat_pos_match = mask_val & !heat_neg;

    wire [7:0] heat_overlay_mag = heat_pos_match ? heat_mag : 8'd0;

    wire [7:0] heat_overlay_r = heat_overlay_mag;
    wire [7:0] heat_overlay_g = (heat_overlay_mag > 8'd128) ? (heat_overlay_mag - 8'd128) << 1 : 8'd0;
    wire [7:0] heat_overlay_b = 8'd0;

    wire [10:0] box_left   = {det_x_ds, 1'b0};
    wire [10:0] box_top    = {det_y_ds, 1'b0};
    wire [10:0] box_size   = BOX_SIZE_DS * 2;
    wire [10:0] box_right  = (box_left + box_size - 1 > 11'd639) ?
                              11'd639 : box_left + box_size - 1;
    wire [10:0] box_bottom = (box_top + box_size - 1 > 11'd479) ?
                              11'd479 : box_top + box_size - 1;

    wire [10:0] px = {1'b0, pixel_x};
    wire [10:0] py = {1'b0, pixel_y};

    wire in_box_h = (px >= box_left) && (px <= box_right);
    wire in_box_v = (py >= box_top)  && (py <= box_bottom);

    wire on_box_left   = in_box_v && (px >= box_left)  && (px < box_left + BOX_THICK);
    wire on_box_right  = in_box_v && (px <= box_right) && (px > box_right - BOX_THICK);
    wire on_box_top    = in_box_h && (py >= box_top)   && (py < box_top + BOX_THICK);
    wire on_box_bottom = in_box_h && (py <= box_bottom) && (py > box_bottom - BOX_THICK);
    wire on_box        = found & overlay_en &
                         (on_box_left | on_box_right | on_box_top | on_box_bottom);

    wire [10:0] center_x = box_left + (box_size >> 1);
    wire [10:0] center_y = box_top  + (box_size >> 1);
    wire on_cross = found & overlay_en &
                    (((py == center_y) && in_box_h) || ((px == center_x) && in_box_v));

    reg [7:0] base_r, base_g, base_b;

    always @(*) begin
        case (mode)
            2'b00: begin
                if (gray_view) begin
                    base_r = gray_hold;
                    base_g = gray_hold;
                    base_b = gray_hold;
                end else begin
                    base_r = cam_r;
                    base_g = cam_g;
                    base_b = cam_b;
                end
            end
            2'b01: begin
                base_r = edge_hold;
                base_g = edge_hold;
                base_b = edge_hold;
            end
            2'b10: begin
                if (heat_pos_match) begin
                    base_r = (cam_r >> 2) + (heat_overlay_r >> 1);
                    base_g = (cam_g >> 2) + (heat_overlay_g >> 1);
                    base_b = (cam_b >> 2);
                end else begin
                    base_r = cam_r;
                    base_g = cam_g;
                    base_b = cam_b;
                end
            end
            default: begin
                base_r = mask_val ? 8'd255 : 8'd0;
                base_g = mask_val ? 8'd255 : 8'd0;
                base_b = mask_val ? 8'd255 : 8'd0;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vga_r <= 8'd0;
            vga_g <= 8'd0;
            vga_b <= 8'd0;
        end else if (!blank_n) begin
            vga_r <= 8'd0;
            vga_g <= 8'd0;
            vga_b <= 8'd0;
        end else if (on_box) begin
            vga_r <= 8'd0;
            vga_g <= 8'd255;
            vga_b <= 8'd0;
        end else if (on_cross) begin
            vga_r <= 8'd255;
            vga_g <= 8'd0;
            vga_b <= 8'd0;
        end else begin
            vga_r <= base_r;
            vga_g <= base_g;
            vga_b <= base_b;
        end
    end

endmodule
