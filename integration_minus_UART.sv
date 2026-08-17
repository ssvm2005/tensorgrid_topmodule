`timescale 1ns / 1ps

module integration_minus_UART #(
    parameter GRID_SIZE = 3
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic [7:0] i_uart_rx_data,
    input logic i_uart_rx_new,
    output logic [7:0] o_uart_tx_data,
    output logic o_uart_tx_new
);
logic quant_ip_reset;
logic signed [22:0] quant_ip_data;
logic [31:0] quant_ip_scale;
logic [7:0] quant_ip_zero_point;
logic [2:0] quant_ip_target_dtype;
logic [7:0] quant_op_data;

logic mac_ip_reset;
logic [9*GRID_SIZE*GRID_SIZE-1:0] mac_ip_a;
logic [9*GRID_SIZE*GRID_SIZE-1:0] mac_ip_b;
logic [GRID_SIZE*GRID_SIZE-1:0] mac_ip_valid;
logic [23*GRID_SIZE*GRID_SIZE-1:0] mac_op_result;

logic rb_ip_matrix_config;
logic rb_ip_matrix_signed;
logic rb_ip_data_load;
logic rb_ip_data_read;
logic rb_ip_shift_row;
logic rb_ip_shift_col;
logic rb_ip_arithmetic_op;
logic [1:0] rb_ip_arithmetic_op_type; // 00: add, 01: element-wise, 10: dot_prod, 11: mat_mul
logic rb_ip_quantization_op;
logic rb_ip_relu_op;
logic rb_ip_clamp_op;
logic [7:0] rb_ip_clamp_max;
logic [1:0] rb_ip_matrix_1;
logic [1:0] rb_ip_matrix_2;
logic [$clog2(GRID_SIZE)-1:0] rb_ip_matrix_rows;
logic [$clog2(GRID_SIZE)-1:0] rb_ip_matrix_cols;
logic [7:0] rb_ip_data;
logic [7:0] rb_op_data_rd;

command_parser #(.GRID_SIZE(GRID_SIZE)) command_parser_inst (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_uart_rx_data(i_uart_rx_data),
    .i_uart_rx_new(i_uart_rx_new),
    .o_uart_tx_data(o_uart_tx_data),
    .o_uart_tx_new(o_uart_tx_new),

    .o_matrix_config(rb_ip_matrix_config),
    .o_matrix_signed(rb_ip_matrix_signed),
    .o_data_load(rb_ip_data_load),
    .o_data_read(rb_ip_data_read),
    .o_shift_row(rb_ip_shift_row),
    .o_shift_col(rb_ip_shift_col),
    .o_arithmetic_op(rb_ip_arithmetic_op),
    .o_arithmetic_op_type(rb_ip_arithmetic_op_type), // 00: add, 01: element-wise, 10: dot_prod, 11: mat_mul
    .o_quantization_op(rb_ip_quantization_op),
    .o_relu_op(rb_ip_relu_op),
    .o_clamp_op(rb_ip_clamp_op),
    .o_clamp_max(rb_ip_clamp_max),
    .o_matrix_1(rb_ip_matrix_1),
    .o_matrix_2(rb_ip_matrix_2),
    .o_matrix_rows(rb_ip_matrix_rows),
    .o_matrix_cols(rb_ip_matrix_cols),
    .o_data(rb_ip_data),
    .i_data_rd(rb_op_data_rd),

    .o_quantizer_scale(quant_ip_scale),
    .o_quantizer_zero_point(quant_ip_zero_point),
    .o_quantizer_target_dtype(quant_ip_target_dtype)
);

reg_bank #(.GRID_SIZE(GRID_SIZE)) reg_bank_inst (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_matrix_config(rb_ip_matrix_config),
    .i_matrix_signed(rb_ip_matrix_signed),
    .i_data_load(rb_ip_data_load),
    .i_data_read(rb_ip_data_read),
    .i_shift_row(rb_ip_shift_row),
    .i_shift_col(rb_ip_shift_col),
    .i_arithmetic_op(rb_ip_arithmetic_op),
    .i_arithmetic_op_type(rb_ip_arithmetic_op_type),
    .i_quantization_op(rb_ip_quantization_op),
    .i_relu_op(rb_ip_relu_op),
    .i_clamp_op(rb_ip_clamp_op),
    .i_clamp_max(rb_ip_clamp_max),
    .i_matrix_1(rb_ip_matrix_1),
    .i_matrix_2(rb_ip_matrix_2),
    .i_matrix_rows(rb_ip_matrix_rows),
    .i_matrix_cols(rb_ip_matrix_cols),
    .i_data(rb_ip_data),
    .o_data_rd(rb_op_data_rd),

    .o_grid_reset(mac_ip_reset),
    .o_data_a(mac_ip_a),
    .o_data_b(mac_ip_b),
    .o_data_valid(mac_ip_valid),
    .i_result(mac_op_result),

    .o_quant_reset(quant_ip_reset),
    .o_quant_ip(quant_ip_data),
    .i_quant_data(quant_op_data)
);

MAC_grid #(.GRID_SIZE(GRID_SIZE)) mac_grid_inst (
    .i_clk(i_clk),
    .i_rst_n(mac_ip_reset),
    .i_data_a(mac_ip_a),
    .i_data_b(mac_ip_b),
    .i_valid(mac_ip_valid),
    .o_result(mac_op_result)
);

quantizer quantizer_inst (
    .i_clk(i_clk),
    .i_rst_n(quant_ip_reset),
    .i_data(quant_ip_data),
    .i_scale(quant_ip_scale),
    .i_zero_point(quant_ip_zero_point),
    .i_target_dtype(quant_ip_target_dtype),
    .o_quantized_data(quant_op_data)
);

endmodule
