`timescale 1 ns / 1 ps

module systolic_template_matcher #(
    parameter IMAGE_WIDTH   = 320,
    parameter TEMPLATE_SIZE = 64,
    parameter ROW_W         = 6,
    parameter COL_W         = 6,
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

    wire [TEMPLATE_SIZE*FEATURE_W-1:0] row_pixels;
    wire                               row_pixels_valid;
    wire                               window_valid;
    wire [X_W-1:0]                     window_x;
    wire [Y_W-1:0]                     window_y;

    // 1. Line buffers to generate KxK window
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

    // 2. Skew the inputs for the systolic array
    logic [TEMPLATE_SIZE-1:0][FEATURE_W-1:0] ifmap_skewed;
    logic [TEMPLATE_SIZE-1:0]                ifmap_valid_skewed;

    genvar r;
    generate
        for (r = 0; r < TEMPLATE_SIZE; r = r + 1) begin : ifmap_skew
            if (r == 0) begin
                assign ifmap_skewed[0] = row_pixels[FEATURE_W-1:0];
                assign ifmap_valid_skewed[0] = window_valid;
            end else begin
                logic [r-1:0][FEATURE_W-1:0] delay_pipe;
                logic [r-1:0]                valid_pipe;
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        delay_pipe <= '0;
                        valid_pipe <= '0;
                    end else begin
                        delay_pipe[0] <= row_pixels[r*FEATURE_W +: FEATURE_W];
                        valid_pipe[0] <= window_valid;
                        for (int i = 1; i < r; i = i + 1) begin
                            delay_pipe[i] <= delay_pipe[i-1];
                            valid_pipe[i] <= valid_pipe[i-1];
                        end
                    end
                end
                assign ifmap_skewed[r] = delay_pipe[r-1];
                assign ifmap_valid_skewed[r] = valid_pipe[r-1];
            end
        end
    endgenerate

    // 3. Weight Loader State Machine
    // We will initialize the array with a simple dense template (e.g. diagonal line)
    // Or load from a memory if required. Here we load a simple edge pattern.
    logic weight_enable;
    logic [TEMPLATE_SIZE-1:0][WEIGHT_W-1:0] weight_data_in;
    logic [$clog2(TEMPLATE_SIZE+1):0] weight_row_counter;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_row_counter <= '0;
            weight_enable <= 1'b0;
        end else begin
            if (weight_row_counter < TEMPLATE_SIZE) begin
                weight_enable <= 1'b1;
                weight_row_counter <= weight_row_counter + 1'b1;
            end else begin
                weight_enable <= 1'b0;
            end
        end
    end

    // Include the dense template
    // If dense_template_64.vh is provided we can load from it, else a default
    // We'll generate a default pattern here for testing:
    always_comb begin
        for (int c = 0; c < TEMPLATE_SIZE; c++) begin
            // Simple diagonal edge template
            if (weight_row_counter == c)
                weight_data_in[c] = 8'sd127;
            else if (weight_row_counter == c + 1 || weight_row_counter + 1 == c)
                weight_data_in[c] = -8'sd64;
            else
                weight_data_in[c] = 8'sd0;
        end
    end

    // 4. Systolic Array Instantiation
    logic [TEMPLATE_SIZE-1:0]                        ofmap_valid_out;
    logic [TEMPLATE_SIZE-1:0][SCORE_W-1:0]           ofmap_data_out;

    PE_Array #(
        .PeArrayRows(TEMPLATE_SIZE),
        .PeArrayColumns(TEMPLATE_SIZE),
        .InputFeatureMapBitWidth(FEATURE_W),
        .WeightBitWidth(WEIGHT_W),
        .OutputFeatureMapBitWidth(SCORE_W)
    ) u_pe_array (
        .Clock(clk),
        .ResetNegative(rst_n),
        .WeightPrefetchIn(1'b0),
        .WeightEnableIn(weight_enable),
        .WeightDataIn(weight_data_in),
        .InputFeatureMapStartIn(1'b0),
        .InputFeatureMapEnableIn(ifmap_valid_skewed),
        .InputFeatureMapDataIn(ifmap_skewed),
        .OutputFeatureMapValidOut(ofmap_valid_out),
        .OutputFeatureMapDataOut(ofmap_data_out)
    );

    // 5. De-skew the outputs from the PE_Array
    logic [TEMPLATE_SIZE-1:0][SCORE_W-1:0] ofmap_deskewed;
    logic                                  ofmap_deskewed_valid;

    genvar c;
    generate
        for (c = 0; c < TEMPLATE_SIZE; c = c + 1) begin : ofmap_deskew
            localparam int DELAY = TEMPLATE_SIZE - 1 - c;
            if (DELAY == 0) begin
                assign ofmap_deskewed[c] = ofmap_data_out[c];
            end else begin
                logic [DELAY-1:0][SCORE_W-1:0] delay_pipe;
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        delay_pipe <= '0;
                    end else begin
                        delay_pipe[0] <= ofmap_data_out[c];
                        for (int i = 1; i < DELAY; i = i + 1) begin
                            delay_pipe[i] <= delay_pipe[i-1];
                        end
                    end
                end
                assign ofmap_deskewed[c] = delay_pipe[DELAY-1];
            end
        end
    endgenerate

    // Match the valid signal (use the last column's valid since it has 0 delay)
    // Wait, the output is valid when the systolic array produces it.
    // The delay pipeline also delays the valid signal.
    // The valid signal from the array for column c is ofmap_valid_out[c].
    // Since we deskew by TEMPLATE_SIZE - 1 - c, the aligned valid is:
    logic [TEMPLATE_SIZE-2:0] valid_deskew_pipe;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_deskew_pipe <= '0;
        end else begin
            valid_deskew_pipe[0] <= ofmap_valid_out[TEMPLATE_SIZE-1]; // last column has no delay
            for (int i = 1; i < TEMPLATE_SIZE-1; i = i + 1) begin
                valid_deskew_pipe[i] <= valid_deskew_pipe[i-1];
            end
        end
    end
    assign ofmap_deskewed_valid = ofmap_valid_out[TEMPLATE_SIZE-1];

    // 6. Adder Tree (Pipelined)
    // To cleanly sum TEMPLATE_SIZE elements, we'll do a simple linear pipeline or registered accumulator.
    // Since we need 1 output per cycle, we can't accumulate over time for the same window.
    // We must spatially sum `ofmap_deskewed` all 64 elements.
    // We will do a 2-stage adder tree to meet timing easily.
    // Stage 1: sum 8 groups of 8 elements.
    localparam NUM_GROUPS = (TEMPLATE_SIZE + 7) / 8;
    logic signed [SCORE_W-1:0] stage1_sum [0:NUM_GROUPS-1];
    logic                      stage1_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int g = 0; g < NUM_GROUPS; g++)
                stage1_sum[g] <= '0;
            stage1_valid <= 1'b0;
        end else begin
            stage1_valid <= ofmap_deskewed_valid;
            for (int g = 0; g < NUM_GROUPS; g++) begin
                logic signed [SCORE_W-1:0] temp_sum;
                temp_sum = '0;
                for (int i = 0; i < 8; i++) begin
                    if (g * 8 + i < TEMPLATE_SIZE)
                        temp_sum = temp_sum + $signed(ofmap_deskewed[g * 8 + i]);
                end
                stage1_sum[g] <= temp_sum;
            end
        end
    end

    // Stage 2: sum the groups
    logic signed [SCORE_W-1:0] stage2_sum;
    logic                      stage2_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage2_sum <= '0;
            stage2_valid <= 1'b0;
        end else begin
            stage2_valid <= stage1_valid;
            logic signed [SCORE_W-1:0] temp_sum;
            temp_sum = '0;
            for (int g = 0; g < NUM_GROUPS; g++) begin
                temp_sum = temp_sum + stage1_sum[g];
            end
            stage2_sum <= temp_sum;
        end
    end

    assign score_out   = stage2_sum;
    assign score_valid = stage2_valid;

    // 7. Delay coordinates to match the systolic array + deskew + adder tree pipeline latency
    // stream_delay_engine gives window_x, window_y corresponding to the CURRENT row_pixels (which is the bottom-right of the window).
    // The systolic array computes the score for this window.
    // Total latency from window_valid to score_valid:
    // IFMAP Skew: row 0 is delayed by 0. row 63 is delayed by 63.
    // PE_Array: outputs for row 63 come out after 64 cycles (vertical) + column latency.
    // Actually, rather than calculating the exact mathematical latency, we can just use a shift register
    // for x and y that moves exactly when the pipeline moves, or just a fixed delay.
    // Wait, `PE_Array` generates `OutputFeatureMapValidOut` based on `InputFeatureMapEnableIn`.
    // Let's count cycles:
    // `ifmap_skew` for row 0: 0 cycles.
    // `PE_Array` column 0: receives row 0 at cycle 0. Outputs PSUM at row 63 after 64 cycles.
    // `ofmap_deskew` for column 0: delays by 63 cycles.
    // Total latency to `ofmap_deskewed`: 64 + 63 = 127 cycles.
    // Adder tree stage 1: 1 cycle.
    // Adder tree stage 2: 1 cycle.
    // Total latency: 129 cycles.
    localparam LATENCY = TEMPLATE_SIZE + TEMPLATE_SIZE - 1 + 2;

    logic [X_W-1:0] x_pipe [0:LATENCY];
    logic [Y_W-1:0] y_pipe [0:LATENCY];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i <= LATENCY; i++) begin
                x_pipe[i] <= '0;
                y_pipe[i] <= '0;
            end
        end else begin
            x_pipe[0] <= window_x;
            y_pipe[0] <= window_y;
            for (int i = 1; i <= LATENCY; i++) begin
                x_pipe[i] <= x_pipe[i-1];
                y_pipe[i] <= y_pipe[i-1];
            end
        end
    end

    assign x_out = x_pipe[LATENCY];
    assign y_out = y_pipe[LATENCY];

endmodule
