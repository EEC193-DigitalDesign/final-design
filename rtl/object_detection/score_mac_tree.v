//=======================================================
// score_mac_tree.v
// Parameterized pipelined MAC backend for sparse template scoring.
//
// This replaces the old hand-unrolled 64-tap-only tree.  NUM_TAPS may be
// any positive integer; the tree pads to the next power of two internally
// and builds the required number of reduction stages at elaboration time.
//
// Inputs:
//   features[t] : unsigned FEATURE_W-bit Sobel magnitude sample
//   weights[t]  : signed WEIGHT_W-bit template weight
//
// Output latency from in_valid to score_valid: clog2(next_pow2(NUM_TAPS))
// clock cycles.  For NUM_TAPS=32 this is 5 clocks; for 64 it is 6 clocks.
//=======================================================
module score_mac_tree #(
    parameter NUM_TAPS  = 32,
    parameter FEATURE_W = 8,
    parameter WEIGHT_W  = 8,
    parameter SCORE_W   = 32
)(
    input                             clk,
    input                             rst_n,
    input      [NUM_TAPS*FEATURE_W-1:0] features,
    input      [NUM_TAPS*WEIGHT_W-1:0]  weights,
    input                             in_valid,

    output signed [SCORE_W-1:0]      score_out,
    output                            score_valid
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

    localparam PAD_TAPS = next_pow2(NUM_TAPS);
    localparam STAGES   = clog2(PAD_TAPS);

    // One extra feature sign bit is used because features are unsigned.
    localparam PROD_W = FEATURE_W + 1 + WEIGHT_W;

    // sum_pipe[0] holds products.  sum_pipe[s+1] holds pairwise sums of
    // sum_pipe[s].  All stages use SCORE_W so the interface width controls
    // final dynamic range.  Use SCORE_W >= PROD_W + STAGES for no overflow.
    reg signed [SCORE_W-1:0] sum_pipe [0:STAGES][0:PAD_TAPS-1];
    reg [STAGES:0]           valid_pipe;

    integer ti;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe[0] <= 1'b0;
            for (ti = 0; ti < PAD_TAPS; ti = ti + 1)
                sum_pipe[0][ti] <= {SCORE_W{1'b0}};
        end else begin
            valid_pipe[0] <= in_valid;
            for (ti = 0; ti < PAD_TAPS; ti = ti + 1) begin
                if (ti < NUM_TAPS) begin
                    sum_pipe[0][ti] <=
                        $signed({1'b0, features[ti*FEATURE_W +: FEATURE_W]}) *
                        $signed(weights[ti*WEIGHT_W +: WEIGHT_W]);
                end else begin
                    sum_pipe[0][ti] <= {SCORE_W{1'b0}};
                end
            end
        end
    end

    genvar s;
    generate
        for (s = 0; s < STAGES; s = s + 1) begin : reduce_stage
            localparam integer N_NEXT = PAD_TAPS >> (s + 1);
            integer j;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    valid_pipe[s+1] <= 1'b0;
                    for (j = 0; j < N_NEXT; j = j + 1)
                        sum_pipe[s+1][j] <= {SCORE_W{1'b0}};
                end else begin
                    valid_pipe[s+1] <= valid_pipe[s];
                    for (j = 0; j < N_NEXT; j = j + 1)
                        sum_pipe[s+1][j] <= sum_pipe[s][2*j] + sum_pipe[s][2*j+1];
                end
            end
        end
    endgenerate

    assign score_out   = sum_pipe[STAGES][0];
    assign score_valid = valid_pipe[STAGES];

endmodule
