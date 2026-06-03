//=======================================================
// rgb_downsample_gray.v
// 640x480 RGB stream -> 320x240 grayscale stream.
// Samples even active-region rows and columns only.
//=======================================================
module rgb_downsample_gray (
    input             clk,
    input             rst_n,
    input             de,
    input      [9:0]  x_in,
    input      [9:0]  y_in,
    input      [7:0]  r_in,
    input      [7:0]  g_in,
    input      [7:0]  b_in,

    output reg        pix_valid,
    output reg [9:0]  x_out,
    output reg [9:0]  y_out,
    output reg [7:0]  gray_out,
    output reg [7:0]  r_out,
    output reg [7:0]  g_out,
    output reg [7:0]  b_out
);

    wire take_sample = de & ~x_in[0] & ~y_in[0] &
                       (x_in < 10'd640) & (y_in < 10'd480);

    wire [15:0] gray_sum = (r_in * 8'd77) + (g_in * 8'd150) + (b_in * 8'd29);
    wire [7:0]  gray     = gray_sum[15:8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pix_valid <= 1'b0;
            x_out     <= 10'd0;
            y_out     <= 10'd0;
            gray_out  <= 8'd0;
            r_out     <= 8'd0;
            g_out     <= 8'd0;
            b_out     <= 8'd0;
        end else begin
            pix_valid <= take_sample;
            if (take_sample) begin
                x_out    <= {1'b0, x_in[9:1]};
                y_out    <= {1'b0, y_in[9:1]};
                gray_out <= gray;
                r_out    <= r_in;
                g_out    <= g_in;
                b_out    <= b_in;
            end
        end
    end

endmodule
