//=======================================================
// sparse_template_matcher.v
// Top-level straightforward sparse Sobel matched-filter matcher.
//
// Replaces the previous fake systolic array.  The datapath is intentionally
// direct and parameterized:
//   feature stream -> row delay engine -> score_tree -> score_mac_tree
//=======================================================
module sparse_template_matcher #(
    parameter IMAGE_WIDTH   = 320,
    parameter TEMPLATE_SIZE = 32,
    parameter NUM_TAPS      = 64,
    parameter ROW_W         = 5,
    parameter COL_W         = 5,
    parameter FEATURE_W     = 8,
    parameter WEIGHT_W      = 8,
    parameter SCORE_W       = 32,
    parameter X_W           = 10,
    parameter Y_W           = 10
)(
    input                          clk,
    input                          rst_n,
    input                          feature_valid,
    input      [X_W-1:0]           x_in,
    input      [Y_W-1:0]           y_in,
    input      [FEATURE_W-1:0]     feature_in,

    output signed [SCORE_W-1:0]    score_out,
    output                         score_valid,
    output     [X_W-1:0]           x_out,
    output     [Y_W-1:0]           y_out
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

    function integer next_pow2;
        input integer value;
        integer p;
        begin
            p = 1;
            while (p < value)
                p = p << 1;
            next_pow2 = p;
        end
    endfunction

    localparam MAC_STAGES         = clog2(next_pow2(NUM_TAPS));
    localparam SCORE_TREE_LATENCY = 1 + MAC_STAGES;

    wire [TEMPLATE_SIZE*FEATURE_W-1:0] row_pixels;
    wire                               row_pixels_valid;
    wire                               window_valid;
    wire [X_W-1:0]                     window_x;
    wire [Y_W-1:0]                     window_y;

    stream_delay_engine #(
        .IMAGE_WIDTH ( IMAGE_WIDTH   ),
        .NUM_ROWS    ( TEMPLATE_SIZE ),
        .NUM_COLS    ( TEMPLATE_SIZE ),
        .FEATURE_W   ( FEATURE_W     ),
        .X_W         ( X_W           ),
        .Y_W         ( Y_W           )
    ) u_stream_delay (
        .clk              ( clk              ),
        .rst_n            ( rst_n            ),
        .pixel_valid      ( feature_valid    ),
        .x_in             ( x_in             ),
        .y_in             ( y_in             ),
        .feature_in       ( feature_in       ),
        .row_pixels       ( row_pixels       ),
        .row_pixels_valid ( row_pixels_valid ),
        .window_valid     ( window_valid     ),
        .x_out            ( window_x         ),
        .y_out            ( window_y         )
    );

    score_tree #(
        .NUM_ROWS  ( TEMPLATE_SIZE ),
        .NUM_COLS  ( TEMPLATE_SIZE ),
        .NUM_TAPS  ( NUM_TAPS      ),
        .ROW_W     ( ROW_W         ),
        .COL_W     ( COL_W         ),
        .FEATURE_W ( FEATURE_W     ),
        .WEIGHT_W  ( WEIGHT_W      ),
        .SCORE_W   ( SCORE_W       )
    ) u_score_tree (
        .clk              ( clk              ),
        .rst_n            ( rst_n            ),
        .row_pixels_valid ( row_pixels_valid ),
        .row_pixels       ( row_pixels       ),
        .in_valid         ( window_valid     ),
        .score_out        ( score_out        ),
        .score_valid      ( score_valid      )
    );

    reg [X_W-1:0] x_pipe [0:SCORE_TREE_LATENCY];
    reg [Y_W-1:0] y_pipe [0:SCORE_TREE_LATENCY];

    integer pi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (pi = 0; pi <= SCORE_TREE_LATENCY; pi = pi + 1) begin
                x_pipe[pi] <= {X_W{1'b0}};
                y_pipe[pi] <= {Y_W{1'b0}};
            end
        end else begin
            x_pipe[0] <= window_x;
            y_pipe[0] <= window_y;
            for (pi = 1; pi <= SCORE_TREE_LATENCY; pi = pi + 1) begin
                x_pipe[pi] <= x_pipe[pi-1];
                y_pipe[pi] <= y_pipe[pi-1];
            end
        end
    end

    assign x_out = x_pipe[SCORE_TREE_LATENCY];
    assign y_out = y_pipe[SCORE_TREE_LATENCY];

endmodule
