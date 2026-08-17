`timescale 1ns / 1ps

module command_parser #(
    parameter GRID_SIZE = 4
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic [7:0] i_uart_rx_data,
    input logic i_uart_rx_new,
    output logic [7:0] o_uart_tx_data,
    output logic o_uart_tx_new,

    output logic o_matrix_config,
    output logic o_matrix_signed,
    output logic o_data_load,
    output logic o_data_read,
    output logic o_shift_row,
    output logic o_shift_col,
    output logic o_arithmetic_op,
    output logic [1:0] o_arithmetic_op_type, // 00: add, 01: element-wise, 10: dot_prod, 11: mat_mul
    output logic o_quantization_op,
    output logic o_relu_op,
    output logic o_clamp_op,
    output logic [7:0] o_clamp_max,
    output logic [1:0] o_matrix_1,
    output logic [1:0] o_matrix_2,
    output logic [$clog2(GRID_SIZE)-1:0] o_matrix_rows,
    output logic [$clog2(GRID_SIZE)-1:0] o_matrix_cols,
    output logic [7:0] o_data,
    input logic [7:0] i_data_rd,
    input logic i_idle,

    output logic [31:0] o_quantizer_scale,
    output logic [7:0] o_quantizer_zero_point,
    output logic [2:0] o_quantizer_target_dtype
);

localparam logic [3:0] OP_QUANTIZE = 4'h1;
localparam logic [2:0] RX_QUANTIZE_BYTES = 3'd7;
localparam logic [3:0] OP_ADD = 4'h4;
localparam logic [3:0] OP_EL_MUL = 4'h5;
localparam logic [3:0] OP_DOT_PROD = 4'h6;
localparam logic [2:0] RX_DOT_PROD_BYTES = 3'd2;
localparam logic [3:0] OP_MAT_MUL = 4'h7;
localparam logic [3:0] OP_MATRIX_CLR = 4'h8;
localparam logic [3:0] OP_LOAD_ELEMENT = 4'h2;
localparam logic [2:0] RX_LOAD_ELEMENT_BYTES = 3'd3;
localparam logic [3:0] OP_READ_ELEMENT = 4'h3;
localparam logic [2:0] RX_READ_ELEMENT_BYTES = 3'd2;
localparam logic [3:0] OP_SHIFT_ROW_COL = 4'hB;
localparam logic [2:0] RX_SHIFT_ROW_COL_BYTES = 3'd2;
localparam logic [3:0] OP_RELU = 4'h9;
localparam logic [3:0] OP_CLAMP = 4'hA;
localparam logic [2:0] RX_CLAMP_BYTES = 3'd2;

//localparam logic [2:0] RX_BYTES_ARR [0:15] = '{3'd1, RX_QUANTIZE_BYTES, RX_LOAD_ELEMENT_BYTES, RX_READ_ELEMENT_BYTES, 3'd1, 3'd1, RX_DOT_PROD_BYTES, 3'd1, 3'd1, 3'd1, RX_CLAMP_BYTES, RX_SHIFT_ROW_COL_BYTES, 3'd1, 3'd1, 3'd1, 3'd1};


function [2:0] expected_bytes; 
	input [3:0] op;
	begin
		case(op)
			OP_QUANTIZE: expected_bytes = RX_QUANTIZE_BYTES;
			OP_DOT_PROD: expected_bytes = RX_DOT_PROD_BYTES;
			OP_LOAD_ELEMENT: expected_bytes = RX_LOAD_ELEMENT_BYTES;
			OP_READ_ELEMENT: expected_bytes = RX_READ_ELEMENT_BYTES;
			OP_SHIFT_ROW_COL: expected_bytes = RX_SHIFT_ROW_COL_BYTES;
			OP_CLAMP: expected_bytes = RX_CLAMP_BYTES;
			default: expected_bytes = 3'd1;
		endcase
	end
endfunction


logic [3:0] byte_count;
logic [3:0] current_op;

// Robust Command Parser FSM / Byte Counter Logic
always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        byte_count <= 4'd0;
        current_op <= 4'd0;
    end else if (i_uart_rx_new) begin
        if (byte_count == 4'd0) begin
            current_op <= i_uart_rx_data[7:4];
            if (expected_bytes(i_uart_rx_data[7:4]) == 3'd1) begin
                byte_count <= 4'd0;
            end else begin
                byte_count <= 4'd1;
            end
        end else begin
            // Check if we have reached the end of a multi-byte packet
            if (byte_count == (expected_bytes(current_op) - 4'd1)) begin
                // If it's a READ command (e.g., OP_READ_ELEMENT), hold or wait 
                // for tx ready instead of instantly resetting if a handshake is needed,
                // OR ensure the read trigger pulse stays active long enough for uartTx to latch.
                byte_count <= 4'd0; 
            end else begin
                byte_count <= byte_count + 4'd1;
            end
        end
    end
end

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_matrix_config <= 1'b0;
        o_matrix_signed <= 1'b0;
        o_data_load <= 1'b0;
        o_data_read <= 1'b0;
        o_shift_row <= 1'b0;
        o_shift_col <= 1'b0;
        o_arithmetic_op <= 1'b0;
        o_arithmetic_op_type <= 2'd0;
        o_quantization_op <= 1'b0;
        o_relu_op <= 1'b0;
        o_clamp_op <= 1'b0;
        o_clamp_max <= 8'd0;
        o_matrix_1 <= 2'd0;
        o_matrix_2 <= 2'd0;
        o_matrix_rows <= '0;
        o_matrix_cols <= '0;
        o_data <= 8'd0;
        o_quantizer_scale <= 32'd0;
        o_quantizer_zero_point <= 8'd0;
        o_quantizer_target_dtype <= 3'd0;
    end else begin
        if (!byte_count) begin
            o_matrix_config <= (i_uart_rx_data[7:4] == OP_MATRIX_CLR) && i_uart_rx_new;
            if (i_uart_rx_data[7:4] == OP_MATRIX_CLR) o_matrix_signed <= i_uart_rx_data[1];
            o_arithmetic_op <= (i_uart_rx_data[7:4] == OP_ADD || i_uart_rx_data[7:4] == OP_EL_MUL || i_uart_rx_data[7:4] == OP_MAT_MUL) && i_uart_rx_new;
            if (i_uart_rx_data[7:6] == 2'b01) o_arithmetic_op_type <= i_uart_rx_data[5:4];
            o_relu_op <= (i_uart_rx_data[7:4] == OP_RELU) && i_uart_rx_new;
            if (i_uart_rx_data[7:4] != 4'h0 && i_uart_rx_data[7:4] < 4'hC) begin
                o_matrix_1 <= i_uart_rx_data[3:2];
                o_matrix_2 <= i_uart_rx_data[1:0];
            end
            o_data_load <= 1'b0;
            o_data_read <= 1'b0;
            o_shift_row <= 1'b0;
            o_shift_col <= 1'b0;
            o_quantization_op <= 1'b0;
            o_clamp_op <= 1'b0;
        end else begin
            if (byte_count == 3'd1) begin
                o_data_read <= (current_op == OP_READ_ELEMENT) && i_uart_rx_new;
                o_shift_row <= (current_op == OP_SHIFT_ROW_COL && i_uart_rx_new && i_uart_rx_data[3]);
                o_shift_col <= (current_op == OP_SHIFT_ROW_COL && i_uart_rx_new && !i_uart_rx_data[3]);
                o_arithmetic_op <= (current_op == OP_DOT_PROD) && i_uart_rx_new;
                o_clamp_op <= (current_op == OP_CLAMP) && i_uart_rx_new;
                if (current_op == OP_CLAMP) o_clamp_max <= i_uart_rx_data;
                if (current_op == OP_QUANTIZE) o_quantizer_target_dtype <= i_uart_rx_data[7:5];
                o_matrix_rows <= i_uart_rx_data[4 +: $clog2(GRID_SIZE)];
                o_matrix_cols <= (current_op == OP_SHIFT_ROW_COL) ? i_uart_rx_data[4 +: $clog2(GRID_SIZE)] : i_uart_rx_data[0 +: $clog2(GRID_SIZE)];
            end else if (byte_count == 3'd2) begin
                o_data_load <= (current_op == OP_LOAD_ELEMENT) && i_uart_rx_new;
                if (current_op == OP_LOAD_ELEMENT) o_data <= i_uart_rx_data;
                if (current_op == OP_QUANTIZE) o_quantizer_zero_point <= i_uart_rx_data;
            end else if (byte_count < 3'd7) begin
                if (current_op == OP_QUANTIZE) begin
                    case (byte_count)
                        3'd3: o_quantizer_scale[31:24] <= i_uart_rx_data;
                        3'd4: o_quantizer_scale[23:16] <= i_uart_rx_data;
                        3'd5: o_quantizer_scale[15:8] <= i_uart_rx_data;
                        3'd6: o_quantizer_scale[7:0] <= i_uart_rx_data;
                    endcase
                    o_quantization_op <= i_uart_rx_new && (byte_count == 3'd6);
                end
            end
        end
    end
end

logic data_read_buf;

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        data_read_buf <= 1'b0;
        o_uart_tx_new <= 1'b0;
        o_uart_tx_data <= 8'd0;
    end else begin
        data_read_buf <= o_data_read;
        o_uart_tx_new <= data_read_buf;
        o_uart_tx_data <= i_data_rd;
    end
end

endmodule