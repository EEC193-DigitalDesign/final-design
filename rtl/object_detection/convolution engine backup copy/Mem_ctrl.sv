`timescale 1 ns / 1 ps

module Mem_ctrl #(
    parameter PeArrayRows = 16,
    parameter PeArrayColumns = 16,
    parameter WeightBitWidth = 8,
    parameter InputFeatureMapBitWidth = 16,
    parameter OutputFeatureMapBitWidth = 32,
    parameter WeightAddressBit = 11, // Bit width of Weight Memory Address
    parameter InputFeatureMapAddressBit = 9, // Bit width of Input Feature Map Address
    parameter OutputFeatureMapAddressBit = 10, // Bit width of Output Feature Map Address
    parameter OutputFeatureMapChannelCount = 64, // Number of output channels
    parameter InputFeatureMapChannelCount = 32, // Number of input channels
    parameter WeightWidth = 3, // Horizontal kernel dimension
    parameter WeightHeight = 3, // Vertical kernel dimension
    parameter InputFeatureMapWidth = 16, // Width of input feature map
    parameter InputFeatureMapHeight = 16, // Height of input feature map
    parameter OutputFeatureMapWidth = 14, // Width of output feature map
    parameter OutputFeatureMapHeight = 14 // Height of output feature map
)(
    input logic Clock,
    input logic ResetNegative,
    input logic StartIn,
    input logic OutputFeatureMapReadyIn,
    output logic WeightPrefetchOut,
    output logic [WeightAddressBit-1:0] WeightAddressOut,
    output logic WeightReadEnableOut,
    output logic InputFeatureMapStartOut,
    output logic [InputFeatureMapAddressBit-1:0] InputFeatureMapAddressOut,
    output logic InputFeatureMapReadEnableOut,
    output logic MacDoneOut,
    output logic [OutputFeatureMapAddressBit-1:0] OutputFeatureMapAddressOut,
    output logic OutputFeatureMapWriteEnableOut,
    output logic OutputFeatureMapWriteDoneOut
);

logic [1:0] State;
localparam IDLE = 2'd0, WEIGHT = 2'd1, IFMAP = 2'd2, WAIT = 2'd3;

localparam NumOutTile = (OutputFeatureMapChannelCount + PeArrayColumns - 1) / PeArrayColumns;
localparam NumInTile = (InputFeatureMapChannelCount + PeArrayRows - 1) / PeArrayRows;
localparam WeightOutStride = NumOutTile * (PeArrayRows - 1);
localparam InputFeatureMapWeightStride = WeightWidth * NumInTile;
localparam InputFeatureMapOfHeightStride = (OutputFeatureMapHeight - 1) * InputFeatureMapWidth * NumInTile - 1;
localparam InputFeatureMapOutStride = ((OutputFeatureMapHeight - 1) * InputFeatureMapWidth + OutputFeatureMapWidth - 1) * NumInTile;
localparam OutputFeatureMapSize = OutputFeatureMapWidth * OutputFeatureMapHeight * NumOutTile;
localparam WaitCycles = (PeArrayColumns == 1) ? 3 : PeArrayColumns;
localparam RowCounterWidth = (PeArrayRows <= 1) ? 1 : $clog2(PeArrayRows);
localparam WaitCounterWidth = (WaitCycles <= 1) ? 1 : $clog2(WaitCycles);
localparam WeightRowWidth = (WeightHeight <= 1) ? 1 : $clog2(WeightHeight);
localparam WeightColWidth = (WeightWidth <= 1) ? 1 : $clog2(WeightWidth);
localparam OutputFeatureMapWidthCounterWidth = (OutputFeatureMapWidth <= 1) ? 1 : $clog2(OutputFeatureMapWidth);
localparam OutputFeatureMapHeightCounterWidth = (OutputFeatureMapHeight <= 1) ? 1 : $clog2(OutputFeatureMapHeight);
localparam OutTileWidth = (NumOutTile <= 1) ? 1 : $clog2(NumOutTile);
localparam InTileWidth = (NumInTile <= 1) ? 1 : $clog2(NumInTile);

logic [RowCounterWidth-1:0] RowCounter;
logic [WaitCounterWidth-1:0] ColCounter;
logic [WeightRowWidth-1:0] RowOffset;
logic [WeightColWidth-1:0] ColOffset;
logic [OutputFeatureMapWidthCounterWidth-1:0] IfWidthCounter;
logic [OutputFeatureMapHeightCounterWidth-1:0] IfHeightCounter;
logic [OutTileWidth-1:0] OutChannelTile;
logic [InTileWidth-1:0] InChannelTile;
logic InputFeatureMapFinish, InputFeatureMapPreFinish, LastTile, LastChannelTile;

assign InputFeatureMapFinish = IfWidthCounter == OutputFeatureMapWidth - 1 && IfHeightCounter == OutputFeatureMapHeight - 1;
assign InputFeatureMapPreFinish = IfHeightCounter == OutputFeatureMapHeight - 1 && IfWidthCounter == OutputFeatureMapWidth - 2;
assign LastChannelTile = OutChannelTile == NumOutTile - 1 && InChannelTile == NumInTile - 1;
assign LastTile = LastChannelTile && RowOffset == WeightHeight - 1 && ColOffset == WeightWidth - 1;
assign OutputFeatureMapWriteEnableOut = OutputFeatureMapReadyIn;

always_ff @(posedge Clock) begin
    if (~ResetNegative) begin
        WeightPrefetchOut <= 1'b0;
        WeightAddressOut <= 0;
        WeightReadEnableOut <= 1'b0;
        InputFeatureMapStartOut <= 1'b0;
        InputFeatureMapAddressOut <= 0;
        InputFeatureMapReadEnableOut <= 1'b0;
        MacDoneOut <= 1'b0;
        State <= IDLE;
        RowCounter <= 0;
        RowOffset <= 0;
        ColOffset <= 0;
        IfWidthCounter <= 0;
        IfHeightCounter <= 0;
        OutChannelTile <= 0;
        InChannelTile <= 0;
        ColCounter <= 0;
    end else begin
        case (State)
            IDLE: begin
                ColCounter <= 0;
                RowCounter <= 0;
                RowOffset <= 0;
                ColOffset <= 0;
                IfWidthCounter <= 0;
                IfHeightCounter <= 0;
                OutChannelTile <= 0;
                InChannelTile <= 0;
                InputFeatureMapAddressOut <= 0;
                if (StartIn) begin
                    State <= WEIGHT;
                    WeightPrefetchOut <= 1'b1;
                    WeightAddressOut <= 0;
                    WeightReadEnableOut <= 1'b1;
                end
            end
            WEIGHT: begin
                WeightPrefetchOut <= 1'b0;
                if (RowCounter == PeArrayRows - 1) begin
                    RowCounter <= 0;
                    WeightReadEnableOut <= 1'b0;
                    State <= IFMAP;
                    InputFeatureMapStartOut <= 1'b1;
                    InputFeatureMapReadEnableOut <= 1'b1;
                end else begin
                    RowCounter <= RowCounter + 1'b1;
                    WeightAddressOut <= WeightAddressOut + NumOutTile;
                end
            end
            IFMAP: begin
                InputFeatureMapStartOut <= 1'b0;
                if (LastTile && InputFeatureMapPreFinish) begin
                    MacDoneOut <= 1'b1;
                end else begin
                    MacDoneOut <= 1'b0;
                end
                if (InputFeatureMapFinish) begin
                    IfWidthCounter <= 0;
                    IfHeightCounter <= 0;
                    InputFeatureMapReadEnableOut <= 1'b0;
                    if (LastTile) begin
                        State <= IDLE;
                    end else begin
                        State <= WAIT;
                        if (LastChannelTile) begin
                            OutChannelTile <= 0;
                            InChannelTile <= 0;
                            WeightAddressOut <= WeightAddressOut + 1'b1;
                            if (ColOffset == WeightWidth - 1) begin
                                RowOffset <= RowOffset + 1'b1;
                                ColOffset <= 0;
                                InputFeatureMapAddressOut <= InputFeatureMapAddressOut - InputFeatureMapOfHeightStride;
                            end else begin
                                ColOffset <= ColOffset + 1'b1;
                                InputFeatureMapAddressOut <= InputFeatureMapAddressOut - InputFeatureMapOutStride + 1'b1;
                            end
                        end else begin
                            if (OutChannelTile == NumOutTile - 1) begin
                                OutChannelTile <= 0;
                                InChannelTile <= InChannelTile + 1'b1;
                                WeightAddressOut <= WeightAddressOut + 1'b1;
                                InputFeatureMapAddressOut <= InputFeatureMapAddressOut - InputFeatureMapOutStride + 1'b1;
                            end else begin
                                OutChannelTile <= OutChannelTile + 1'b1;
                                WeightAddressOut <= WeightAddressOut - WeightOutStride + 1'b1;
                                InputFeatureMapAddressOut <= InputFeatureMapAddressOut - InputFeatureMapOutStride;
                            end
                        end
                    end
                end else begin
                    if (IfWidthCounter == OutputFeatureMapWidth - 1) begin
                        IfWidthCounter <= 0;
                        IfHeightCounter <= IfHeightCounter + 1'b1;
                        InputFeatureMapAddressOut <= InputFeatureMapAddressOut + InputFeatureMapWeightStride;
                    end else begin
                        IfWidthCounter <= IfWidthCounter + 1'b1;
                        InputFeatureMapAddressOut <= InputFeatureMapAddressOut + NumInTile;
                    end
                end
            end
            WAIT: begin
                if (ColCounter < WaitCycles - 1) begin
                    ColCounter <= ColCounter + 1'b1;
                end else begin
                    ColCounter <= 0;
                    State <= WEIGHT;
                    WeightPrefetchOut <= 1'b1;
                    WeightReadEnableOut <= 1'b1;
                end
            end
        endcase
    end
end

always @(posedge Clock) begin
    if (~ResetNegative) begin
        OutputFeatureMapAddressOut <= {OutputFeatureMapAddressBit{1'b0}};
        OutputFeatureMapWriteDoneOut <= 1'b0;
    end else begin
        if (OutputFeatureMapReadyIn) begin
            if (OutputFeatureMapAddressOut < OutputFeatureMapSize - NumOutTile) begin
                OutputFeatureMapAddressOut <= OutputFeatureMapAddressOut + NumOutTile;
            end else if (OutputFeatureMapAddressOut == OutputFeatureMapSize - 1) begin
                OutputFeatureMapAddressOut <= 0;
            end else begin
                OutputFeatureMapAddressOut <= OutputFeatureMapAddressOut - (OutputFeatureMapSize - NumOutTile) + 1;
            end
            if (State == IDLE) begin
                if (OutputFeatureMapAddressOut == OutputFeatureMapSize - 1 - NumOutTile) begin
                    OutputFeatureMapWriteDoneOut <= 1'b1;
                end else begin
                    OutputFeatureMapWriteDoneOut <= 1'b0;
                end
            end
        end
    end
end
endmodule