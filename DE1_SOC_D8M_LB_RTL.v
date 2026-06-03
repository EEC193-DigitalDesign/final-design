//=======================================================
// DE1-SoC / D8M Sobel Edge Sparse Matched-Filter Detector
// 640x480 camera -> 320x240 grayscale/Sobel -> sparse donut matcher
//=======================================================
module DE1_SOC_D8M_LB_RTL(

    //////////// CLOCK //////////
    input                CLOCK2_50,
    input                CLOCK3_50,
    input                CLOCK4_50,
    input                CLOCK_50,

    //////////// SEG7 //////////
    output      [6:0]    HEX0,
    output      [6:0]    HEX1,
    output      [6:0]    HEX2,
    output      [6:0]    HEX3,
    output      [6:0]    HEX4,
    output      [6:0]    HEX5,

    //////////// KEY //////////
    input       [3:0]    KEY,

    //////////// LED //////////
    output      [9:0]    LEDR,

    //////////// SW //////////
    input       [9:0]    SW,

    //////////// VGA //////////
    output               VGA_BLANK_N,
    output      [7:0]    VGA_B,
    output               VGA_CLK,
    output      [7:0]    VGA_G,
    output reg           VGA_HS,
    output      [7:0]    VGA_R,
    output               VGA_SYNC_N,
    output reg           VGA_VS,

    //////////// Audio (unused, tied off) //////////
    input                AUD_ADCDAT,
    inout                AUD_ADCLRCK,
    inout                AUD_BCLK,
    output               AUD_DACDAT,
    inout                AUD_DACLRCK,
    output               AUD_XCK,

    //////////// FPGA I2C (unused) //////////
    output               FPGA_I2C_SCLK,
    inout                FPGA_I2C_SDAT,

    //////////// GPIO_1 -> D8M-GPIO //////////
    inout                CAMERA_I2C_SCL,
    inout                CAMERA_I2C_SDA,
    output               CAMERA_PWDN_n,
    output               MIPI_CS_n,
    inout                MIPI_I2C_SCL,
    inout                MIPI_I2C_SDA,
    output               MIPI_MCLK,
    input                MIPI_PIXEL_CLK,
    input       [9:0]    MIPI_PIXEL_D,
    input                MIPI_PIXEL_HS,
    input                MIPI_PIXEL_VS,
    output               MIPI_REFCLK,
    output               MIPI_RESET_n
);

//=============================================================================
// Parameters
//=============================================================================
localparam SCORE_W       = 32;
localparam TEMPLATE_SIZE = 64;
localparam DS_WIDTH      = 320;
localparam ROW_W         = 6;
localparam COL_W         = 6;

localparam MF_NUM_TAPS   = 64;

//=============================================================================
// Audio tie-off (not used)
//=============================================================================
assign AUD_DACDAT    = 1'b0;
assign AUD_XCK       = 1'b0;
assign FPGA_I2C_SCLK = 1'b0;

//=============================================================================
// Switch / Key map
//=============================================================================
// SW[0]   : Detection enable
// SW[2:1] : VGA display mode
//           00=camera RGB/grayscale, 01=Sobel edge,
//           10=signed score heatmap with auto-contrast, 11=mask
// SW[3]   : Detection overlay on/off
// SW[4]   : In mode 00, show grayscale instead of RGB
// SW[9]   : KEY[1]/KEY[2] adjust selector
//           0=matcher detection threshold, 1=Sobel edge threshold
// SW[8:5] : reserved
//
// KEY[0]  : System reset (active-low)
// KEY[1]  : Selected threshold decrease
// KEY[2]  : Selected threshold increase
// KEY[3]  : Autofocus trigger (active-low)

wire       det_enable = SW[0];
wire [1:0] vga_mode   = SW[2:1];
wire       overlay_en = SW[3];
wire       gray_view  = SW[4];
wire       edge_thresh_mode = SW[9];

//=============================================================================
// Core wires
//=============================================================================
wire        AUTO_FOC;
wire        READ_Request;
wire  [7:0] VGA_R_A, VGA_G_A, VGA_B_A;
wire  [7:0] VGA_R_unfilt, VGA_G_unfilt, VGA_B_unfilt;
wire        VGA_CLK_25M;
wire        RESET_N;
wire  [7:0] sCCD_R, sCCD_G, sCCD_B;
wire [15:0] H_Cont, V_Cont;
wire        I2C_RELEASE;
wire        CAMERA_I2C_SCL_MIPI, CAMERA_I2C_SCL_AF;
wire        CAMERA_MIPI_RELAESE, MIPI_BRIDGE_RELEASE;
wire        D8M_CK_HZ, D8M_CK_HZ2, D8M_CK_HZ3;
wire        RESET_KEY;
wire        LUT_MIPI_PIXEL_HS, LUT_MIPI_PIXEL_VS;
wire [9:0]  LUT_MIPI_PIXEL_D;
wire        MIPI_PIXEL_CLK_;

//=============================================================================
// Detection pipeline wires
//=============================================================================
wire        ds_valid;
wire [9:0]  ds_x, ds_y;
wire [7:0]  ds_gray;
wire [7:0]  ds_r, ds_g, ds_b;

wire        edge_valid;
wire [9:0]  edge_x, edge_y;
wire [7:0]  edge_mag;

wire signed [SCORE_W-1:0] mf_score;
wire                      mf_score_valid;
wire [9:0]                mf_x, mf_y;

wire        det_found;
wire [9:0]  det_x_ds, det_y_ds;
wire [SCORE_W-1:0] det_confidence;

//=============================================================================
// Adjustable thresholds (KEY[1] down, KEY[2] up)
//=============================================================================
localparam signed [SCORE_W-1:0] DETECT_THRESH_INIT = 32'sd30000;
localparam signed [SCORE_W-1:0] DETECT_THRESH_STEP = 32'sd4096;
localparam signed [SCORE_W-1:0] DETECT_THRESH_MAX  = 32'sd2000000;

// Raw Sobel L1 maximum is about 2040: |gx|max 1020 + |gy|max 1020.
localparam [12:0] EDGE_THRESH_INIT = 13'd330;
localparam [12:0] EDGE_THRESH_STEP = 13'd32;
localparam [12:0] EDGE_THRESH_MAX  = 13'd2040;

reg signed [SCORE_W-1:0] detect_thresh;
reg [12:0] edge_thresh_l1;
reg        key1_d, key2_d;
reg [19:0] key_lockout;

always @(posedge CLOCK_50 or negedge RESET_N) begin
    if (!RESET_N) begin
        detect_thresh  <= DETECT_THRESH_INIT;
        edge_thresh_l1 <= EDGE_THRESH_INIT;
        key1_d <= 1'b1;
        key2_d <= 1'b1;
        key_lockout <= 20'd0;
    end else begin
        key1_d <= KEY[1];
        key2_d <= KEY[2];
        if (key_lockout > 20'd0) begin
            key_lockout <= key_lockout - 20'd1;
        end else begin
            if (~KEY[1] & key1_d) begin
                if (edge_thresh_mode) begin
                    if (edge_thresh_l1 > EDGE_THRESH_STEP)
                        edge_thresh_l1 <= edge_thresh_l1 - EDGE_THRESH_STEP;
                    else
                        edge_thresh_l1 <= 13'd0;
                end else begin
                    if (detect_thresh > DETECT_THRESH_STEP)
                        detect_thresh <= detect_thresh - DETECT_THRESH_STEP;
                    else
                        detect_thresh <= 32'sd0;
                end
                key_lockout <= 20'hFFFFF;
            end
            if (~KEY[2] & key2_d) begin
                if (edge_thresh_mode) begin
                    if (edge_thresh_l1 < (EDGE_THRESH_MAX - EDGE_THRESH_STEP))
                        edge_thresh_l1 <= edge_thresh_l1 + EDGE_THRESH_STEP;
                    else
                        edge_thresh_l1 <= EDGE_THRESH_MAX;
                end else begin
                    if (detect_thresh < DETECT_THRESH_MAX)
                        detect_thresh <= detect_thresh + DETECT_THRESH_STEP;
                end
                key_lockout <= 20'hFFFFF;
            end
        end
    end
end

//=============================================================================
// Camera infrastructure
//=============================================================================
assign MIPI_PIXEL_CLK_   = MIPI_PIXEL_CLK;
assign LUT_MIPI_PIXEL_HS = MIPI_PIXEL_HS;
assign LUT_MIPI_PIXEL_VS = MIPI_PIXEL_VS;
assign LUT_MIPI_PIXEL_D  = MIPI_PIXEL_D;
assign RESET_KEY         = KEY[0];

RESET_DELAY u2(
    .iRST  ( RESET_KEY ),
    .iCLK  ( CLOCK2_50 ),
    .oREADY( RESET_N )
);

assign MIPI_RESET_n  = RESET_N;
assign CAMERA_PWDN_n = RESET_KEY;
assign MIPI_CS_n     = 1'b0;
assign MIPI_MCLK     = MIPI_REFCLK;

assign I2C_RELEASE    = CAMERA_MIPI_RELAESE & MIPI_BRIDGE_RELEASE;
assign CAMERA_I2C_SCL = I2C_RELEASE ? CAMERA_I2C_SCL_AF : CAMERA_I2C_SCL_MIPI;

MIPI_BRIDGE_CAMERA_Config cfin(
    .RESET_N           ( RESET_N ),
    .CLK_50            ( CLOCK2_50 ),
    .MIPI_I2C_SCL      ( MIPI_I2C_SCL ),
    .MIPI_I2C_SDA      ( MIPI_I2C_SDA ),
    .MIPI_I2C_RELEASE  ( MIPI_BRIDGE_RELEASE ),
    .CAMERA_I2C_SCL    ( CAMERA_I2C_SCL_MIPI ),
    .CAMERA_I2C_SDA    ( CAMERA_I2C_SDA ),
    .CAMERA_I2C_RELAESE( CAMERA_MIPI_RELAESE )
);

pll_test pll_ref(
    .refclk   ( CLOCK_50 ),
    .rst      ( 1'b0 ),
    .outclk_0 ( MIPI_REFCLK )
);

vga_pll pllv(
    .refclk   ( CLOCK4_50 ),
    .rst      ( 1'b0 ),
    .outclk_0 ( VGA_CLK_25M )
);

//=============================================================================
// D8M RAW -> RGB
//=============================================================================
D8M_SET ccd(
    .RESET_SYS_N ( RESET_N ),
    .CLOCK_50    ( CLOCK2_50 ),
    .CCD_DATA    ( LUT_MIPI_PIXEL_D[9:0] ),
    .CCD_FVAL    ( LUT_MIPI_PIXEL_VS ),
    .CCD_LVAL    ( LUT_MIPI_PIXEL_HS ),
    .CCD_PIXCLK  ( MIPI_PIXEL_CLK_ ),
    .READ_EN     ( READ_Request ),
    .VGA_HS      ( VGA_HS ),
    .VGA_VS      ( VGA_VS ),
    .X_Cont      ( H_Cont ),
    .Y_Cont      ( V_Cont ),
    .sCCD_R      ( sCCD_R ),
    .sCCD_G      ( sCCD_G ),
    .sCCD_B      ( sCCD_B )
);

//=============================================================================
// VGA timing
//=============================================================================
assign VGA_CLK    = MIPI_PIXEL_CLK_;
assign VGA_SYNC_N = 1'b0;

assign READ_Request = ((H_Cont > 16'd160 && H_Cont < 16'd800) &&
                       (V_Cont > 16'd045 && V_Cont < 16'd525));

assign VGA_BLANK_N = ~((H_Cont < 16'd160) || (V_Cont < 16'd045));

assign VGA_R_A = VGA_BLANK_N ? sCCD_R : 8'h00;
assign VGA_G_A = VGA_BLANK_N ? sCCD_G : 8'h00;
assign VGA_B_A = VGA_BLANK_N ? sCCD_B : 8'h00;

always @(*) begin
    VGA_HS = !((H_Cont >= 16'd002) && (H_Cont <= 16'd097));
    VGA_VS = !((V_Cont >= 16'd013) && (V_Cont <= 16'd014));
end

//=============================================================================
// Autofocus (KEY[3] triggers focus)
//=============================================================================
AUTO_FOCUS_ON adj(
    .CLK_50      ( CLOCK2_50 ),
    .I2C_RELEASE ( I2C_RELEASE ),
    .AUTO_FOC    ( AUTO_FOC )
);

FOCUS_ADJ adl(
    .CLK_50        ( CLOCK2_50 ),
    .RESET_N       ( I2C_RELEASE ),
    .RESET_SUB_N   ( I2C_RELEASE ),
    .AUTO_FOC      ( KEY[3] & AUTO_FOC ),
    .SW_FUC_LINE   ( 1'b0 ),
    .SW_FUC_ALL_CEN( 1'b0 ),
    .VIDEO_HS      ( VGA_HS ),
    .VIDEO_VS      ( VGA_VS ),
    .VIDEO_CLK     ( VGA_CLK ),
    .VIDEO_DE      ( READ_Request ),
    .iR            ( VGA_R_A ),
    .iG            ( VGA_G_A ),
    .iB            ( VGA_B_A ),
    .oR            ( VGA_R_unfilt ),
    .oG            ( VGA_G_unfilt ),
    .oB            ( VGA_B_unfilt ),
    .READY         ( ),
    .SCL           ( CAMERA_I2C_SCL_AF ),
    .SDA           ( CAMERA_I2C_SDA )
);

//=============================================================================
// Active-region coordinates
//=============================================================================
wire [9:0] active_col_raw = (H_Cont > 16'd160) ? (H_Cont[9:0] - 10'd161) : 10'd0;
wire [9:0] active_row_raw = (V_Cont > 16'd045) ? (V_Cont[9:0] - 10'd046) : 10'd0;

wire [9:0] pixel_x = active_col_raw;
wire [9:0] pixel_y = active_row_raw;

//=============================================================================
// Detector pipeline: downsample -> grayscale -> Sobel -> direct sparse MAC-tree matcher
//=============================================================================
rgb_downsample_gray u_downsample (
    .clk       ( MIPI_PIXEL_CLK_ ),
    .rst_n     ( RESET_N ),
    .de        ( READ_Request ),
    .x_in      ( active_col_raw ),
    .y_in      ( active_row_raw ),
    .r_in      ( VGA_R_unfilt ),
    .g_in      ( VGA_G_unfilt ),
    .b_in      ( VGA_B_unfilt ),
    .pix_valid ( ds_valid ),
    .x_out     ( ds_x ),
    .y_out     ( ds_y ),
    .gray_out  ( ds_gray ),
    .r_out     ( ds_r ),
    .g_out     ( ds_g ),
    .b_out     ( ds_b )
);

sobel3x3_stream #(
    .IMAGE_WIDTH(DS_WIDTH)
) u_sobel (
    .clk       ( MIPI_PIXEL_CLK_ ),
    .rst_n     ( RESET_N ),
    .pix_valid ( ds_valid ),
    .x_in      ( ds_x ),
    .y_in      ( ds_y ),
    .pix_in    ( ds_gray ),
    .edge_thresh_l1 ( edge_thresh_l1 ),
    .mag_out   ( edge_mag ),
    .mag_valid ( edge_valid ),
    .x_out     ( edge_x ),
    .y_out     ( edge_y )
);

sparse_template_matcher #(
    .IMAGE_WIDTH  ( DS_WIDTH ),
    .TEMPLATE_SIZE( TEMPLATE_SIZE ),
    .NUM_TAPS     ( MF_NUM_TAPS ),
    .ROW_W        ( ROW_W ),
    .COL_W        ( COL_W ),
    .FEATURE_W    ( 8 ),
    .WEIGHT_W     ( 8 ),
    .SCORE_W      ( SCORE_W ),
    .X_W          ( 10 ),
    .Y_W          ( 10 )
) u_matcher (
    .clk           ( MIPI_PIXEL_CLK_ ),
    .rst_n         ( RESET_N ),
    .feature_valid ( edge_valid & det_enable ),
    .x_in          ( edge_x ),
    .y_in          ( edge_y ),
    .feature_in    ( edge_mag ),
    .score_out     ( mf_score ),
    .score_valid   ( mf_score_valid ),
    .x_out         ( mf_x ),
    .y_out         ( mf_y )
);

detection_logic #(
    .SCORE_W       ( SCORE_W ),
    .TEMPLATE_SIZE ( TEMPLATE_SIZE )
) u_detect (
    .clk         ( MIPI_PIXEL_CLK_ ),
    .rst_n       ( RESET_N ),
    .score       ( mf_score ),
    .score_valid ( mf_score_valid ),
    .x_score     ( mf_x ),
    .y_score     ( mf_y ),
    .vs          ( VGA_VS ),
    .threshold   ( detect_thresh ),
    .found       ( det_found ),
    .det_x       ( det_x_ds ),
    .det_y       ( det_y_ds ),
    .confidence  ( det_confidence )
);

//=============================================================================
// VGA debug display mux
//=============================================================================
vga_debug_mux #(
    .SCORE_W     ( SCORE_W ),
    .BOX_SIZE_DS ( TEMPLATE_SIZE ),
    .BOX_THICK   ( 2 ),
    .DS_WIDTH    ( 320 ),
    .DS_HEIGHT   ( 240 ),
    .VGA_WIDTH   ( 640 ),
    .VGA_HEIGHT  ( 480 ),
    .SCORE_SHIFT ( 10 ),
    .AUTOCONTRAST_EN ( 1 )
) u_vga_mux (
    .clk         ( MIPI_PIXEL_CLK_ ),
    .rst_n       ( RESET_N ),
    .mode        ( vga_mode ),
    .overlay_en  ( overlay_en ),
    .gray_view   ( gray_view ),
    .cam_r       ( VGA_R_unfilt ),
    .cam_g       ( VGA_G_unfilt ),
    .cam_b       ( VGA_B_unfilt ),
    .gray        ( ds_gray ),
    .gray_valid  ( ds_valid ),
    .edge_mag    ( edge_mag ),
    .edge_valid  ( edge_valid ),
    .score       ( mf_score ),
    .score_valid ( mf_score_valid ),
    .score_x     ( mf_x ),
    .score_y     ( mf_y ),
    .threshold   ( detect_thresh ),
    .found       ( det_found ),
    .det_x_ds    ( det_x_ds ),
    .det_y_ds    ( det_y_ds ),
    .pixel_x     ( pixel_x ),
    .pixel_y     ( pixel_y ),
    .blank_n     ( VGA_BLANK_N ),
    .frame_sync  ( VGA_VS ),
    .vga_r       ( VGA_R ),
    .vga_g       ( VGA_G ),
    .vga_b       ( VGA_B )
);

//=============================================================================
// HEX displays
//=============================================================================
// HEX1:HEX0 - Frame rate
FpsMonitor uFps2(
    .clk50    ( CLOCK2_50 ),
    .vs       ( VGA_VS ),
    .fps      ( ),
    .hex_fps_h( HEX1 ),
    .hex_fps_l( HEX0 )
);

// HEX3:HEX2 - Selected threshold summary
// SW[9]=0: detection threshold[19:12]
// SW[9]=1: edge threshold / 16
wire [7:0] thresh_disp = edge_thresh_mode ? edge_thresh_l1[11:4] : detect_thresh[19:12];
SEG7_LUT h2( .iDIG( thresh_disp[3:0] ), .oSEG( HEX2 ) );
SEG7_LUT h3( .iDIG( thresh_disp[7:4] ), .oSEG( HEX3 ) );

// HEX5:HEX4 - Confidence summary, blank if not found
wire [7:0] conf_disp = det_confidence[19:12];
wire [6:0] hex4_seg, hex5_seg;
SEG7_LUT h4( .iDIG( conf_disp[3:0] ), .oSEG( hex4_seg ) );
SEG7_LUT h5( .iDIG( conf_disp[7:4] ), .oSEG( hex5_seg ) );
assign HEX4 = det_found ? hex4_seg : 7'h7F;
assign HEX5 = det_found ? hex5_seg : 7'h7F;

//=============================================================================
// LEDs
//=============================================================================
assign LEDR[9]   = det_found;
assign LEDR[8]   = mf_score_valid;
assign LEDR[7]   = det_enable;
assign LEDR[6]   = overlay_en;
assign LEDR[5:2] = vga_mode == 2'b00 ? 4'b0001 :
                    vga_mode == 2'b01 ? 4'b0010 :
                    vga_mode == 2'b10 ? 4'b0100 : 4'b1000;
assign LEDR[1]   = CAMERA_MIPI_RELAESE;
assign LEDR[0]   = D8M_CK_HZ3;

//=============================================================================
// Clock frequency monitors (debug)
//=============================================================================
CLOCKMEM ck1( .CLK(VGA_CLK_25M),     .CLK_FREQ(25000000), .CK_1HZ(D8M_CK_HZ)  );
CLOCKMEM ck2( .CLK(MIPI_REFCLK),     .CLK_FREQ(20000000), .CK_1HZ(D8M_CK_HZ2) );
CLOCKMEM ck3( .CLK(MIPI_PIXEL_CLK_), .CLK_FREQ(25000000), .CK_1HZ(D8M_CK_HZ3) );

endmodule
