`timescale 1 ns / 1 ps

module Systolic_Top #(
    parameter PeArrayRows = 16,
    parameter PeArrayColumns = 16,
    parameter WeightBitWidth = 8,
    parameter InputFeatureMapBitWidth = 16,
    parameter OutputFeatureMapBitWidth = 32,
    parameter WeightAddressBit = 12,
    parameter InputFeatureMapAddressBit = 9,
    parameter OutputFeatureMapAddressBit = 10,
    parameter OutputFeatureMapChannelCount = 64,
    parameter InputFeatureMapChannelCount = 32,
    parameter WeightWidth = 3,
    parameter WeightHeight = 3,
    parameter InputFeatureMapWidth = 16,
    parameter InputFeatureMapHeight = 16,
    parameter OutputFeatureMapWidth = 14,
    parameter OutputFeatureMapHeight = 14,
    parameter InputFeatureMapDataPath = "", // Path for Input Data Init
    parameter WeightDataPath = "", // Path for Weight Data Init
    parameter OutputFeatureMapDataPath = "" // Path for Output Data Init
)(
    input logic Clock,
    input logic ResetNegative,
    input logic [OutputFeatureMapAddressBit-1:0] TestOutputAddressIn,
    input logic TestCheckIn,
    output logic [PeArrayColumns*OutputFeatureMapBitWidth-1:0] TestOutputOut,
    input logic StartIn,
    output logic FinishOut
);

localparam NumOutTile = (OutputFeatureMapChannelCount + PeArrayColumns - 1) / PeArrayColumns;
localparam OutputFeatureMapSize = OutputFeatureMapWidth * OutputFeatureMapHeight * NumOutTile;

logic [PeArrayColumns-1:0][WeightBitWidth-1:0] WeightData;
logic [WeightAddressBit-1:0] WeightAddress;
logic [PeArrayRows-1:0][InputFeatureMapBitWidth-1:0] InputFeatureMapData;
logic [InputFeatureMapAddressBit-1:0] InputFeatureMapAddress;
logic [PeArrayColumns-1:0][OutputFeatureMapBitWidth-1:0] OutputFeatureMapWriteData;
logic [OutputFeatureMapAddressBit-1:0] OutputFeatureMapAddress;
logic OutputFeatureMapWriteEnable;
logic signed [PeArrayColumns-1:0][OutputFeatureMapBitWidth-1:0] PartialSumData;
logic [OutputFeatureMapAddressBit-1:0] PartialSumAddress;
logic [OutputFeatureMapAddressBit-1:0] PartialSumAddressMux;
logic WeightPrefetch;
logic WeightReadEnable;
logic ArrayWeightReadEnable;
logic MemCtrlInputFeatureMapStart;
logic MemCtrlInputFeatureMapReadEnable;
logic [PeArrayRows-1:0] FifoInputFeatureMapReadEnable;
logic FifoInputFeatureMapWriteEnable;
logic [PeArrayRows-1:0][InputFeatureMapBitWidth-1:0] FifoInputFeatureMapDataOut;
logic [PeArrayColumns-1:0][OutputFeatureMapBitWidth-1:0] FifoOutputFeatureMapDataIn;
logic [PeArrayColumns-1:0] FifoOutputFeatureMapWriteEnable;
logic [PeArrayColumns-1:0][OutputFeatureMapBitWidth-1:0] AlignedOutputFeatureMapData;
logic RepeatedOutputFeatureMap;
logic [PeArrayRows-1:0][InputFeatureMapBitWidth-1:0] InputFeatureMapBuffer;
logic [PeArrayRows-1:0] InputFeatureMapReadEnableDelay;
logic [PeArrayColumns-1:0][OutputFeatureMapBitWidth-1:0] OutputFeatureMapBuffer;
logic OutputFeatureMapReady;
logic OutputFeatureMapPrefetchValid;
logic OutputFeatureMapReadySource;
logic [OutputFeatureMapAddressBit-1:0] NextPartialSumAddress;

assign FifoInputFeatureMapDataOut[0] = InputFeatureMapData[PeArrayRows-1];
assign NextPartialSumAddress = PartialSumAddress + NumOutTile;

generate
    for (genvar i = 0; i < PeArrayColumns; i++) begin : gen_wdata
        assign OutputFeatureMapWriteData[i] = OutputFeatureMapBuffer[i];
    end
endgenerate

always_ff @(posedge Clock) begin
    if (~ResetNegative) begin
        PartialSumAddress <= 0;
        ArrayWeightReadEnable <= 1'b0;
        FifoInputFeatureMapReadEnable[0] <= 1'b0;
        FifoInputFeatureMapWriteEnable <= 1'b0;
    end else begin
        ArrayWeightReadEnable <= WeightReadEnable;
        FifoInputFeatureMapReadEnable[0] <= MemCtrlInputFeatureMapReadEnable;
        FifoInputFeatureMapWriteEnable <= MemCtrlInputFeatureMapReadEnable;
        InputFeatureMapReadEnableDelay <= FifoInputFeatureMapReadEnable;
        InputFeatureMapBuffer <= FifoInputFeatureMapDataOut;
        OutputFeatureMapReady <= OutputFeatureMapReadySource;
        for (int i = 0; i < PeArrayColumns; i++) begin
            OutputFeatureMapBuffer[i] <= AlignedOutputFeatureMapData[i];
        end
        if (OutputFeatureMapPrefetchValid) begin
            PartialSumAddress <= NextPartialSumAddress;
        end else begin
            PartialSumAddress <= OutputFeatureMapAddress;
        end
    end
end

always_ff @(posedge Clock) begin
    if (~ResetNegative) begin
        RepeatedOutputFeatureMap <= 1'b0;
    end else begin
        if ((RepeatedOutputFeatureMap || OutputFeatureMapAddress == OutputFeatureMapSize - 1) && ~FinishOut) begin
            RepeatedOutputFeatureMap <= 1'b1;
        end else begin
            RepeatedOutputFeatureMap <= 1'b0;
        end
    end
end

PE_Array #(
    .PeArrayRows(PeArrayRows),
    .PeArrayColumns(PeArrayColumns),
    .InputFeatureMapBitWidth(InputFeatureMapBitWidth),
    .WeightBitWidth(WeightBitWidth),
    .OutputFeatureMapBitWidth(OutputFeatureMapBitWidth)
) PE_Array_instance (
    .Clock(Clock),
    .ResetNegative(ResetNegative),
    .WeightPrefetchIn(WeightPrefetch),
    .WeightEnableIn(ArrayWeightReadEnable),
    .WeightDataIn(WeightData),
    .InputFeatureMapStartIn(MemCtrlInputFeatureMapStart),
    .InputFeatureMapEnableIn(InputFeatureMapReadEnableDelay),
    .InputFeatureMapDataIn(InputFeatureMapBuffer),
    .OutputFeatureMapValidOut(FifoOutputFeatureMapWriteEnable),
    .OutputFeatureMapDataOut(FifoOutputFeatureMapDataIn)
);

Mem_ctrl #(
    .PeArrayRows(PeArrayRows),
    .PeArrayColumns(PeArrayColumns),
    .WeightBitWidth(WeightBitWidth),
    .InputFeatureMapBitWidth(InputFeatureMapBitWidth),
    .OutputFeatureMapBitWidth(OutputFeatureMapBitWidth),
    .WeightAddressBit(WeightAddressBit),
    .InputFeatureMapAddressBit(InputFeatureMapAddressBit),
    .OutputFeatureMapAddressBit(OutputFeatureMapAddressBit),
    .OutputFeatureMapChannelCount(OutputFeatureMapChannelCount),
    .InputFeatureMapChannelCount(InputFeatureMapChannelCount),
    .WeightWidth(WeightWidth),
    .WeightHeight(WeightHeight),
    .InputFeatureMapWidth(InputFeatureMapWidth),
    .InputFeatureMapHeight(InputFeatureMapHeight),
    .OutputFeatureMapWidth(OutputFeatureMapWidth),
    .OutputFeatureMapHeight(OutputFeatureMapHeight)
) Mem_ctrl_instance (
    .Clock(Clock),
    .ResetNegative(ResetNegative),
    .StartIn(StartIn),
    .OutputFeatureMapReadyIn(OutputFeatureMapReady),
    .WeightPrefetchOut(WeightPrefetch),
    .WeightAddressOut(WeightAddress),
    .WeightReadEnableOut(WeightReadEnable),
    .InputFeatureMapStartOut(MemCtrlInputFeatureMapStart),
    .InputFeatureMapAddressOut(InputFeatureMapAddress),
    .InputFeatureMapReadEnableOut(MemCtrlInputFeatureMapReadEnable),
    .MacDoneOut(),
    .OutputFeatureMapAddressOut(OutputFeatureMapAddress),
    .OutputFeatureMapWriteEnableOut(OutputFeatureMapWriteEnable),
    .OutputFeatureMapWriteDoneOut(FinishOut)
);

generate
    genvar r;
    genvar c;
    for (r = 1; r < PeArrayRows; r++) begin : ifMap
        always_ff @(posedge Clock) begin
            FifoInputFeatureMapReadEnable[r] <= FifoInputFeatureMapReadEnable[r-1];
        end
        FIFO #(
            .DataWidth(InputFeatureMapBitWidth),
            .LogDepth($clog2(r+1)),
            .FifoDepth()
        ) ifMapFIFO (
            .Clock(Clock),
            .ResetNegative(ResetNegative),
            .WriteRequest(FifoInputFeatureMapWriteEnable),
            .ReadRequest(FifoInputFeatureMapReadEnable[r]),
            .DataIn(InputFeatureMapData[PeArrayRows-1-r]),
            .DataOut(FifoInputFeatureMapDataOut[r]),
            .Full(),
            .Empty()
        );
    end
    if (PeArrayColumns == 1) begin : ofMapDelaySingleCol
        logic [1:0][OutputFeatureMapBitWidth-1:0] DelayData;
        logic [1:0] DelayValid;
        always_ff @(posedge Clock) begin
            if (~ResetNegative) begin
                DelayData <= '0;
                DelayValid <= 2'b00;
            end else begin
                DelayData[0] <= FifoOutputFeatureMapDataIn[0];
                DelayData[1] <= DelayData[0];
                DelayValid[0] <= FifoOutputFeatureMapWriteEnable[0];
                DelayValid[1] <= DelayValid[0];
            end
        end
        assign AlignedOutputFeatureMapData[0] = DelayData[1];
        assign OutputFeatureMapPrefetchValid = FifoOutputFeatureMapWriteEnable[0];
        assign OutputFeatureMapReadySource = DelayValid[1];
    end else begin : ofMapDelayMultiCol
        assign OutputFeatureMapPrefetchValid = FifoOutputFeatureMapWriteEnable[PeArrayColumns-2];
        assign OutputFeatureMapReadySource = FifoOutputFeatureMapWriteEnable[PeArrayColumns-1];
        for (c = 0; c < PeArrayColumns-1; c++) begin : ofMapDelay
            localparam int Delay = PeArrayColumns - 1 - c;
            logic [Delay-1:0][OutputFeatureMapBitWidth-1:0] DelayPipe;
            always_ff @(posedge Clock) begin
                if (~ResetNegative) begin
                    DelayPipe <= '0;
                end else begin
                    DelayPipe[0] <= FifoOutputFeatureMapDataIn[c];
                    for (int i = 1; i < Delay; i++) begin
                        DelayPipe[i] <= DelayPipe[i-1];
                    end
                end
            end
            assign AlignedOutputFeatureMapData[c] = DelayPipe[Delay-1];
        end
        assign AlignedOutputFeatureMapData[PeArrayColumns-1] = FifoOutputFeatureMapDataIn[PeArrayColumns-1];
    end
endgenerate

assign TestOutputOut = PartialSumData;
assign PartialSumAddressMux = TestCheckIn ? TestOutputAddressIn : PartialSumAddress;

ifmap_mem #(
    .Width(InputFeatureMapBitWidth*PeArrayRows),
    .Depth(1 << InputFeatureMapAddressBit),
    .DataBitWidth(InputFeatureMapBitWidth),
    .PeArrayRows(PeArrayRows),
    .InputFeatureMapChannelCount(InputFeatureMapChannelCount),
    .InputFeatureMapWidth(InputFeatureMapWidth),
    .InputFeatureMapHeight(InputFeatureMapHeight)
) i_mem (
    .Address(InputFeatureMapAddress),
    .Clock(Clock),
    .Data({(InputFeatureMapBitWidth*PeArrayRows){1'b0}}),
    .WriteEnable(1'b0),
    .DataOut(InputFeatureMapData)
);

weight_mem #(
    .Width(WeightBitWidth*PeArrayColumns),
    .Depth(1 << WeightAddressBit),
    .DataBitWidth(WeightBitWidth),
    .PeArrayRows(PeArrayRows),
    .PeArrayColumns(PeArrayColumns),
    .OutputFeatureMapChannelCount(OutputFeatureMapChannelCount),
    .InputFeatureMapChannelCount(InputFeatureMapChannelCount),
    .WeightWidth(WeightWidth),
    .WeightHeight(WeightHeight)
) w_mem (
    .Address(WeightAddress),
    .Clock(Clock),
    .Data({(WeightBitWidth*PeArrayColumns){1'b0}}),
    .WriteEnable(1'b0),
    .DataOut(WeightData)
);

ofmap_mem #(
    .Width(OutputFeatureMapBitWidth*PeArrayColumns),
    .Depth(1 << OutputFeatureMapAddressBit),
    .DataBitWidth(OutputFeatureMapBitWidth),
    .PeArrayColumns(PeArrayColumns)
) o_mem (
    .Clock(Clock),
    .Data(OutputFeatureMapWriteData),
    .ReadAddress(PartialSumAddressMux),
    .WriteAddress(OutputFeatureMapAddress),
    .WriteEnable(OutputFeatureMapWriteEnable),
    .Accumulate(RepeatedOutputFeatureMap),
    .DataOut(PartialSumData)
);
endmodule