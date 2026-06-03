//=======================================================
// stream_delay_engine.v
// Coordinate-driven streaming row-delay engine.
//
// FIX: keep the physical line-buffer RAM pattern in a small leaf module.
// The previous version declared 63 separate 320x8 memories inside a generate
// loop. Quartus mapped those memories to register/LAB muxes instead of M10Ks,
// which caused the fitter to require far more LABs than the device has.
//=======================================================

module stream_delay_line_ram #(
    parameter IMAGE_WIDTH = 320,
    parameter FEATURE_W   = 8,
    parameter X_W         = 10
)(
    input                      clk,
    input                      en,
    input      [X_W-1:0]       addr,
    input      [FEATURE_W-1:0] din,
    output reg [FEATURE_W-1:0] dout
);
    // Keep this as a simple, isolated synchronous read/write RAM so Quartus
    // recognizes one M10K per line buffer instead of building a 320:1 LAB mux.
    (* ramstyle = "M10K, no_rw_check" *) reg [FEATURE_W-1:0] mem [0:IMAGE_WIDTH-1];

    always @(posedge clk) begin
        if (en) begin
            dout      <= mem[addr];
            mem[addr] <= din;
        end
    end
endmodule

module stream_delay_engine #(
    parameter IMAGE_WIDTH = 320,
    parameter NUM_ROWS    = 64,
    parameter NUM_COLS    = 64,
    parameter FEATURE_W   = 8,
    parameter X_W         = 10,
    parameter Y_W         = 10
)(
    input                         clk,
    input                         rst_n,
    input                         pixel_valid,
    input      [X_W-1:0]          x_in,
    input      [Y_W-1:0]          y_in,
    input      [FEATURE_W-1:0]    feature_in,

    output [NUM_ROWS*FEATURE_W-1:0] row_pixels,
    output                        row_pixels_valid,
    output                        window_valid,
    output [X_W-1:0]              x_out,
    output [Y_W-1:0]              y_out
);

    localparam PIPE_LATENCY = NUM_ROWS - 1;

    reg [PIPE_LATENCY-1:0] valid_pipe;
    reg [PIPE_LATENCY-1:0] window_valid_pipe;
    reg [X_W-1:0]          x_pipe [0:PIPE_LATENCY-1];
    reg [Y_W-1:0]          y_pipe [0:PIPE_LATENCY-1];

    wire window_valid_now = pixel_valid &&
                            (x_in >= (NUM_COLS - 1)) &&
                            (y_in >= (NUM_ROWS - 1));

    assign row_pixels_valid = valid_pipe[PIPE_LATENCY-1];
    assign window_valid     = window_valid_pipe[PIPE_LATENCY-1];
    assign x_out            = x_pipe[PIPE_LATENCY-1];
    assign y_out            = y_pipe[PIPE_LATENCY-1];

    integer pi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe        <= {PIPE_LATENCY{1'b0}};
            window_valid_pipe <= {PIPE_LATENCY{1'b0}};
            for (pi = 0; pi < PIPE_LATENCY; pi = pi + 1) begin
                x_pipe[pi] <= {X_W{1'b0}};
                y_pipe[pi] <= {Y_W{1'b0}};
            end
        end else begin
            valid_pipe[0]        <= pixel_valid;
            window_valid_pipe[0] <= window_valid_now;
            x_pipe[0]            <= x_in;
            y_pipe[0]            <= y_in;

            for (pi = 1; pi < PIPE_LATENCY; pi = pi + 1) begin
                valid_pipe[pi]        <= valid_pipe[pi-1];
                window_valid_pipe[pi] <= window_valid_pipe[pi-1];
                x_pipe[pi]            <= x_pipe[pi-1];
                y_pipe[pi]            <= y_pipe[pi-1];
            end
        end
    end

    // Cascaded synchronous line buffers. stage_data[0] is current row;
    // stage_data[d] is delayed by d rows after alignment below.
    wire [FEATURE_W-1:0] stage_data [0:NUM_ROWS-1];
    assign stage_data[0] = feature_in;

    generate
        genvar d;
        for (d = 0; d < NUM_ROWS-1; d = d + 1) begin : line_buffer
            wire stage_en = (d == 0) ? pixel_valid : valid_pipe[d-1];
            wire [X_W-1:0] stage_x = (d == 0) ? x_in : x_pipe[d-1];

            stream_delay_line_ram #(
                .IMAGE_WIDTH ( IMAGE_WIDTH ),
                .FEATURE_W   ( FEATURE_W   ),
                .X_W         ( X_W         )
            ) u_line_ram (
                .clk  ( clk             ),
                .en   ( stage_en        ),
                .addr ( stage_x         ),
                .din  ( stage_data[d]   ),
                .dout ( stage_data[d+1] )
            );
        end
    endgenerate

    // Align every row tap to the deepest row-delay output for the same column.
    wire [FEATURE_W-1:0] aligned_data [0:NUM_ROWS-1];

    generate
        genvar r;
        for (r = 0; r < NUM_ROWS; r = r + 1) begin : align_rows
            if (r == NUM_ROWS-1) begin : no_extra_delay
                assign aligned_data[r] = stage_data[r];
            end else begin : extra_delay
                localparam integer ALIGN_DEPTH = NUM_ROWS - 1 - r;
                reg [FEATURE_W-1:0] pipe [0:ALIGN_DEPTH-1];
                integer j;
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        for (j = 0; j < ALIGN_DEPTH; j = j + 1)
                            pipe[j] <= {FEATURE_W{1'b0}};
                    end else begin
                        pipe[0] <= stage_data[r];
                        for (j = 1; j < ALIGN_DEPTH; j = j + 1)
                            pipe[j] <= pipe[j-1];
                    end
                end
                assign aligned_data[r] = pipe[ALIGN_DEPTH-1];
            end
        end
    endgenerate

    // Pack top-to-bottom: row 0 in the template is the oldest available row.
    generate
        genvar gi;
        for (gi = 0; gi < NUM_ROWS; gi = gi + 1) begin : pack_rows
            assign row_pixels[gi*FEATURE_W +: FEATURE_W] = aligned_data[NUM_ROWS-1-gi];
        end
    endgenerate

endmodule
