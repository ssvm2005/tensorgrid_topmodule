`timescale 1ns / 1ps

module MAC_grid #(
    parameter GRID_SIZE = 8
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic [9*GRID_SIZE*GRID_SIZE-1:0] i_data_a,
    input logic [9*GRID_SIZE*GRID_SIZE-1:0] i_data_b,
    input logic [GRID_SIZE*GRID_SIZE-1:0] i_valid,
    output logic [23*GRID_SIZE*GRID_SIZE-1:0] o_result,
    output logic [GRID_SIZE*GRID_SIZE-1:0] o_valid,
    output logic [GRID_SIZE*GRID_SIZE-1:0] o_overflow
);
logic signed [8:0] data_a_array [GRID_SIZE*GRID_SIZE];
logic signed [8:0] data_b_array [GRID_SIZE*GRID_SIZE];
logic valid_array [GRID_SIZE*GRID_SIZE];
logic signed [22:0] result_array [GRID_SIZE*GRID_SIZE];
logic valid_out_array [GRID_SIZE*GRID_SIZE];
logic overflow_array [GRID_SIZE*GRID_SIZE];

generate
    for (genvar i = 0; i < GRID_SIZE; i++) begin : ROW_LOOP
        for (genvar j = 0; j < GRID_SIZE; j++) begin : COL_LOOP
            assign data_a_array[i*GRID_SIZE+j] = i_data_a[9*(i*GRID_SIZE+j+1)-1 -: 9];
            assign data_b_array[i*GRID_SIZE+j] = i_data_b[9*(i*GRID_SIZE+j+1)-1 -: 9];
            assign valid_array[i*GRID_SIZE+j] = i_valid[i*GRID_SIZE+j];
            assign o_result[23*(i*GRID_SIZE+j+1)-1 -: 23] = result_array[i*GRID_SIZE+j];
            assign o_valid[i*GRID_SIZE+j] = valid_out_array[i*GRID_SIZE+j];
            assign o_overflow[i*GRID_SIZE+j] = overflow_array[i*GRID_SIZE+j];

            int_MAC mac_inst (
                .i_clk(i_clk),
                .i_rst_n(i_rst_n),
                .i_valid(valid_array[i*GRID_SIZE+j]),
                .i_a(data_a_array[i*GRID_SIZE+j]),
                .i_b(data_b_array[i*GRID_SIZE+j]),
                .o_result(result_array[i*GRID_SIZE+j]),
                .o_valid(valid_out_array[i*GRID_SIZE+j]),
                .o_overflow(overflow_array[i*GRID_SIZE+j])
            );
        end
    end
endgenerate

endmodule
