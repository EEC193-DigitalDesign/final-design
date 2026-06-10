`timescale 1 ns / 1 ps

module PE_Array #(
    parameter PeArrayRows = 16, // Number of rows in the processing element array
    parameter PeArrayColumns = 16, // Number of columns in the processing element array
    parameter InputFeatureMapBitWidth = 16,
    parameter WeightBitWidth = 8,
    parameter OutputFeatureMapBitWidth = 32
)(
    input logic Clock,
    input logic ResetNegative,
    input logic WeightPrefetchIn,
    input logic WeightEnableIn,
    input logic [PeArrayColumns-1:0][WeightBitWidth-1:0] WeightDataIn,
    input logic InputFeatureMapStartIn,
    input logic [PeArrayRows-1:0] InputFeatureMapEnableIn,
    input logic [PeArrayRows-1:0][InputFeatureMapBitWidth-1:0] InputFeatureMapDataIn,
    output logic [PeArrayColumns-1:0] OutputFeatureMapValidOut,
    output logic [PeArrayColumns-1:0][OutputFeatureMapBitWidth-1:0] OutputFeatureMapDataOut
);

logic [InputFeatureMapBitWidth-1:0] ConnectInputData [PeArrayRows][PeArrayColumns+1];
logic ConnectInputEnable [PeArrayRows][PeArrayColumns+1];
logic [OutputFeatureMapBitWidth-1:0] ConnectOutputData [PeArrayRows+1][PeArrayColumns];
logic OutputFeatureMapValidBuffer;
localparam int RowCounterWidth = (PeArrayRows <= 1) ? 1 : $clog2(PeArrayRows);
logic [RowCounterWidth-1:0] WeightLoadRow;

always_ff @(posedge Clock) begin
    if (~ResetNegative) begin
        OutputFeatureMapValidOut <= {PeArrayColumns{1'b0}};
        WeightLoadRow <= '0;
    end else begin
        if (WeightEnableIn) begin
            if (WeightLoadRow == PeArrayRows-1) begin
                WeightLoadRow <= '0;
            end else begin
                WeightLoadRow <= WeightLoadRow + 1'b1;
            end
        end
        OutputFeatureMapValidBuffer <= ConnectInputEnable[PeArrayRows-1][0];
        OutputFeatureMapValidOut[0] <= OutputFeatureMapValidBuffer;
        for (int i = 1; i < PeArrayColumns; i++) begin
            OutputFeatureMapValidOut[i] <= OutputFeatureMapValidOut[i-1];
        end
    end
end

generate
    genvar r;
    genvar c;
    for (c = 0; c < PeArrayColumns; c++) begin : initRow
        assign ConnectOutputData[0][c] = {OutputFeatureMapBitWidth{1'b0}};
        assign OutputFeatureMapDataOut[c] = ConnectOutputData[PeArrayRows][c];
    end
    for (r = 0; r < PeArrayRows; r++) begin : initCol
        assign ConnectInputEnable[r][0] = InputFeatureMapEnableIn[r];
        assign ConnectInputData[r][0] = InputFeatureMapDataIn[r];
    end
    for (r = 0; r < PeArrayRows; r++) begin : row
        for (c = 0; c < PeArrayColumns; c++) begin : col
            PE #(
                .InputFeatureMapBitWidth(InputFeatureMapBitWidth),
                .WeightBitWidth(WeightBitWidth),
                .OutputFeatureMapBitWidth(OutputFeatureMapBitWidth)
            ) PE_instance (
                .Clock(Clock),
                .ResetNegative(ResetNegative),
                .WeightEnableIn(WeightEnableIn && (WeightLoadRow == r)),
                .WeightValidIn(1'b1),
                .WeightDataIn(WeightDataIn[c]),
                .WeightDataOut(),
                .WeightValidOut(),
                .InputFeatureMapEnableIn(ConnectInputEnable[r][c]),
                .InputFeatureMapDataIn(ConnectInputData[r][c]),
                .InputFeatureMapValidOut(ConnectInputEnable[r][c+1]),
                .InputFeatureMapDataOut(ConnectInputData[r][c+1]),
                .PartialSumDataIn(ConnectOutputData[r][c]),
                .PartialSumDataOut(ConnectOutputData[r+1][c])
            );
        end
    end
endgenerate
endmodule