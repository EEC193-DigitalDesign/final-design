`timescale 1ns / 1ps

module FIFO #(
    parameter int DataWidth = 16, // Bit width of the data being stored
    parameter int LogDepth = 3, // Logarithmic depth of the FIFO
    parameter int FifoDepth = 16 // Total number of entries in the FIFO
)(
    input logic Clock,
    input logic ResetNegative,
    input logic WriteRequest,
    input logic ReadRequest,
    input logic [DataWidth-1:0] DataIn,
    output logic [DataWidth-1:0] DataOut,
    output logic Full,
    output logic Empty
);

localparam int ActualDepth = 16;
localparam int PointerWidth = 4;

logic [DataWidth-1:0] Memory [0:ActualDepth-1];
logic [PointerWidth-1:0] WritePointer;
logic [PointerWidth-1:0] ReadPointer;
logic [PointerWidth:0] EntryCount;

assign Full = (EntryCount == ActualDepth);
assign Empty = (EntryCount == 0);

assign DataOut = Memory[ReadPointer];

always_ff @(posedge Clock) begin
    if (~ResetNegative) begin
        WritePointer <= '0;
        ReadPointer <= '0;
        EntryCount <= '0;
    end else begin
        if (WriteRequest && !Full) begin
            Memory[WritePointer] <= DataIn;
            WritePointer <= (WritePointer == ActualDepth - 1) ? '0 : WritePointer + 1;
        end

        if (ReadRequest && !Empty) begin
            ReadPointer <= (ReadPointer == ActualDepth - 1) ? '0 : ReadPointer + 1;
        end

        if ((WriteRequest && !Full) && !(ReadRequest && !Empty)) begin
            EntryCount <= EntryCount + 1;
        end else if (!(WriteRequest && !Full) && (ReadRequest && !Empty)) begin
            EntryCount <= EntryCount - 1;
        end
    end
end
endmodule