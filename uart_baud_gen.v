`timescale 1ns / 1ps

module baudGenExt (
    input  wire       clr,                       // global reset input
    input  wire       clk,                       // global clock input
    input  wire [31:0] baudFreq,                 // baud rate setting registers - see header description//115200
    input  wire [31:0] baudLimit,                // baud rate setting registers - see header description //230400
    output reg        ce16                       // baud rate multiplied by 16
);

    reg [31:0] counter;

    always @(posedge clk ) begin
        if (clr) begin
            counter <= 32'b0;
            ce16 <= 1'b0;
        end else begin
            if (counter >= baudLimit) begin
                counter <= counter - baudLimit;
                ce16 <= 1'b1;
            end else begin
                counter <= counter + baudFreq;
                ce16 <= 1'b0;
            end
        end
    end

endmodule