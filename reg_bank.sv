`timescale 1ns / 1ps

module reg_bank #(
    parameter GRID_SIZE = 3
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic i_matrix_config,
    input logic i_matrix_signed,
    input logic i_data_load,
    input logic i_data_read,
    input logic i_shift_row,
    input logic i_shift_col,
    input logic i_arithmetic_op,
    input logic [1:0] i_arithmetic_op_type, // 00: add, 01: element-wise, 10: dot_prod, 11: mat_mul
    input logic i_quantization_op,
    input logic i_relu_op,
    input logic i_clamp_op,
    input logic [7:0] i_clamp_max,
    input logic [1:0] i_matrix_1,
    input logic [1:0] i_matrix_2,
    input logic [$clog2(GRID_SIZE)-1:0] i_matrix_rows,
    input logic [$clog2(GRID_SIZE)-1:0] i_matrix_cols,
    input logic [7:0] i_data,
    output logic [7:0] o_data_rd,
    output logic o_idle,
    
    output logic o_grid_reset,
    output logic [9*GRID_SIZE*GRID_SIZE-1:0] o_data_a,
    output logic [9*GRID_SIZE*GRID_SIZE-1:0] o_data_b,
    output logic [GRID_SIZE*GRID_SIZE-1:0] o_data_valid,
    input logic [23*GRID_SIZE*GRID_SIZE-1:0] i_result,

    output logic o_quant_reset,
    output logic signed [22:0] o_quant_ip,
    input logic [7:0] i_quant_data
);
typedef enum logic [2:0] {
    IDLE = 3'b000,
    ADD = 3'b001,
    EL_MUL = 3'b010,
    MAT_MUL = 3'b011,
    DOT_PROD = 3'b100,
    QUANTIZATION = 3'b101
} state_t;

logic [2:0] current_state, next_state;
logic matrix_signed [4];

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) current_state <= IDLE;
    else current_state <= next_state;
end

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) for (int i = 0; i < 4; i++) matrix_signed[i] <= 1'b0;
    else if (i_matrix_config) matrix_signed[i_matrix_1] <= i_matrix_signed;
end

logic [1:0] matrix_sel_a, matrix_sel_b;
logic [$clog2(GRID_SIZE)-1:0] rows_a, cols_a, rows_b, cols_b;
logic [$clog2(GRID_SIZE)-1:0] matrix_rows_st, matrix_cols_st;

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        matrix_sel_a <= 2'd0;
        matrix_sel_b <= 2'd0;
        matrix_rows_st <= 'd0;
        matrix_cols_st <= 'd0;
    end else if (current_state == IDLE) begin
        matrix_sel_a <= i_matrix_1;
        matrix_sel_b <= i_matrix_2;
        matrix_rows_st <= i_matrix_rows;
        matrix_cols_st <= i_matrix_cols;
    end
end

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        rows_a <= 0;
        cols_a <= 0;
        rows_b <= 0;
        cols_b <= 0;
    end else begin
        case (current_state)
            DOT_PROD: begin
                rows_a <= rows_a + 1;
                rows_b <= rows_b + 1;
                if (rows_a == GRID_SIZE-1) begin
                    rows_a <= 0;
                    rows_b <= 0;
                    cols_a <= cols_a + 1;
                    cols_b <= cols_b + 1;
                    if (cols_a == GRID_SIZE-1) begin
                        rows_a <= rows_a;
                        rows_b <= rows_b;
                        cols_a <= cols_a;
                        cols_b <= cols_b;
                    end
                end
            end
            MAT_MUL: begin
                cols_a <= cols_a + 1;
                rows_b <= rows_b + 1;
                if (cols_a == GRID_SIZE-1) begin
                    cols_a <= cols_a;
                    rows_b <= rows_b;
                end
            end
            QUANTIZATION: begin
                rows_a <= rows_a + 1;
                if (rows_a == GRID_SIZE-1) begin
                    rows_a <= 0;
                    cols_a <= cols_a + 1;
                    if (cols_a == GRID_SIZE-1) begin
                        rows_a <= rows_a;
                        cols_a <= cols_a;
                    end
                end
            end
            default: begin
                rows_a <= 'd0;
                cols_a <= 'd0;
                rows_b <= 'd0;
                cols_b <= 'd0;
            end
        endcase
    end
end

logic [2:0] oper_ctr;

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) oper_ctr <= 3'd0;
    else begin
        case (current_state)
            ADD, EL_MUL: oper_ctr <= oper_ctr + 1;
            MAT_MUL: begin
                if (cols_a == GRID_SIZE-1) oper_ctr <= oper_ctr + 1;
                else oper_ctr <= 3'd0;
            end
            DOT_PROD, QUANTIZATION: begin
                if (rows_a == GRID_SIZE-1 && cols_a == GRID_SIZE-1) oper_ctr <= oper_ctr + 1;
                else oper_ctr <= 3'd0;
            end
            default: oper_ctr <= 3'd0;
        endcase
    end
end

always_comb begin
    next_state = current_state;
    case (current_state)
        IDLE: begin
            if (i_arithmetic_op) begin
                case (i_arithmetic_op_type)
                    2'b00: next_state = ADD;
                    2'b01: next_state = EL_MUL;
                    2'b11: next_state = MAT_MUL;
                    2'b10: next_state = DOT_PROD;
                    default: next_state = IDLE;
                endcase
            end else if (i_quantization_op) next_state = QUANTIZATION;
        end
        ADD, QUANTIZATION: if (oper_ctr == 3'd4) next_state = IDLE;
        EL_MUL, MAT_MUL, DOT_PROD: if (oper_ctr == 3'd3) next_state = IDLE;
        default: next_state = IDLE;
    endcase
end

logic [7:0] mat_arr [4][GRID_SIZE][GRID_SIZE];
logic signed [22:0] accum [GRID_SIZE][GRID_SIZE];

assign o_grid_reset = !(current_state == IDLE || current_state == QUANTIZATION);

always @* begin
    for (int i = 0; i < GRID_SIZE; i++) begin
        for (int j = 0; j < GRID_SIZE; j++) begin
            if (current_state == ADD) o_data_valid[i*GRID_SIZE + j] = oper_ctr < 3'd2;
            else if (current_state == IDLE || current_state == QUANTIZATION) o_data_valid[i*GRID_SIZE + j] = 1'b0;
            else if (current_state == DOT_PROD) o_data_valid[i*GRID_SIZE + j] = (i == 0 && j == 0) ? !oper_ctr : 1'b0;
            else o_data_valid[i*GRID_SIZE + j] = !oper_ctr;
            case (current_state)
                ADD: begin
                    case (oper_ctr)
                        3'd0: o_data_a[9*(i*GRID_SIZE + j) +: 9] = {(matrix_signed[matrix_sel_a] && mat_arr[matrix_sel_a][i][j][7]) , mat_arr[matrix_sel_a][i][j]};
                        3'd1: o_data_a[9*(i*GRID_SIZE + j) +: 9] = {(matrix_signed[matrix_sel_b] && mat_arr[matrix_sel_b][i][j][7]) , mat_arr[matrix_sel_b][i][j]};
                        default: o_data_a[9*(i*GRID_SIZE + j) +: 9] = 9'd0;
                    endcase
                    o_data_b[9*(i*GRID_SIZE + j) +: 9] = 9'd1;
                end
                EL_MUL: begin
                    o_data_a[9*(i*GRID_SIZE + j) +: 9] = {(matrix_signed[matrix_sel_a] && mat_arr[matrix_sel_a][i][j][7]) , mat_arr[matrix_sel_a][i][j]};
                    o_data_b[9*(i*GRID_SIZE + j) +: 9] = {(matrix_signed[matrix_sel_b] && mat_arr[matrix_sel_b][i][j][7]) , mat_arr[matrix_sel_b][i][j]};
                end
                MAT_MUL: begin
                    o_data_a[9*(i*GRID_SIZE + j) +: 9] = {(matrix_signed[matrix_sel_a] && mat_arr[matrix_sel_a][i][cols_a][7]) , mat_arr[matrix_sel_a][i][cols_a]};
                    o_data_b[9*(i*GRID_SIZE + j) +: 9] = {(matrix_signed[matrix_sel_b] && mat_arr[matrix_sel_b][rows_b][j][7]) , mat_arr[matrix_sel_b][rows_b][j]};
                end
                DOT_PROD: begin
                    if (i == 0 && j == 0) begin
                        o_data_a[9*(i*GRID_SIZE + j) +: 9] = {(matrix_signed[matrix_sel_a] && mat_arr[matrix_sel_a][rows_a][cols_a][7]) , mat_arr[matrix_sel_a][rows_a][cols_a]};
                        o_data_b[9*(i*GRID_SIZE + j) +: 9] = {(matrix_signed[matrix_sel_b] && mat_arr[matrix_sel_b][rows_b][cols_b][7]) , mat_arr[matrix_sel_b][rows_b][cols_b]};
                    end else begin
                        o_data_a[9*(i*GRID_SIZE + j) +: 9] = 9'd0;
                        o_data_b[9*(i*GRID_SIZE + j) +: 9] = 9'd0;
                    end
                end
                default: begin
                    o_data_a[9*(i*GRID_SIZE + j) +: 9] = 9'd0;
                    o_data_b[9*(i*GRID_SIZE + j) +: 9] = 9'd0;
                end
            endcase
        end
    end
end

logic [$clog2(GRID_SIZE)-1:0] rows_a_d [4];
logic [$clog2(GRID_SIZE)-1:0] cols_a_d [4];

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        for (int i = 0; i < 4; i++) begin
            rows_a_d[i] <= 'd0;
            cols_a_d[i] <= 'd0;
        end
    end else begin
        for (int i = 0; i < 4; i++) begin
            rows_a_d[i] <= i ? rows_a_d[i-1] : rows_a;
            cols_a_d[i] <= i ? cols_a_d[i-1] : cols_a;
        end
    end
end

assign o_quant_reset = current_state == QUANTIZATION;

always_comb begin
    if (current_state == QUANTIZATION) begin
        o_quant_ip = accum[rows_a][cols_a];
    end else begin
        o_quant_ip = 23'd0;
    end
end

assign o_idle = (current_state == IDLE);

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        for (int j = 0; j < GRID_SIZE; j++) for (int k = 0; k < GRID_SIZE; k++) begin
            accum[j][k] <= 23'd0;
            for (int i = 0; i < 4; i++) mat_arr[i][j][k] <= 8'd0;
        end
    end else begin
        case (current_state)
            ADD: begin
                if (oper_ctr == 3'd4) begin
                    for (int i = 0; i < GRID_SIZE; i++) for (int j = 0; j < GRID_SIZE; j++) accum[i][j] <= i_result[23*(i*GRID_SIZE + j) +: 23];
                end
            end
            EL_MUL, MAT_MUL: begin
                if (oper_ctr == 3'd3) begin
                    for (int i = 0; i < GRID_SIZE; i++) for (int j = 0; j < GRID_SIZE; j++) accum[i][j] <= i_result[23*(i*GRID_SIZE + j) +: 23];
                end
            end
            DOT_PROD: if (oper_ctr == 3'd3) accum[matrix_rows_st][matrix_cols_st] <= i_result[0 +: 23];
            QUANTIZATION: begin
                mat_arr[matrix_sel_a][rows_a_d[3]][cols_a_d[3]] <= i_quant_data;
            end
            IDLE: begin
                if (i_matrix_config) begin
                    for (int i = 0; i < GRID_SIZE; i++) for (int j = 0; j < GRID_SIZE; j++) mat_arr[i_matrix_1][i][j] <= 8'd0;
                end else if (i_data_load) begin
                    mat_arr[i_matrix_1][i_matrix_rows][i_matrix_cols] <= i_data;
                end else if (i_shift_row) begin
                    for (int i = 0; i < GRID_SIZE; i++) for (int j = 0; j < GRID_SIZE; j++) begin
                        if (i < GRID_SIZE - i_matrix_rows) mat_arr[i_matrix_1][i][j] <= mat_arr[i_matrix_1][i + i_matrix_rows][j];
                        else mat_arr[i_matrix_1][i][j] <= 8'd0;
                    end
                end else if (i_shift_col) begin
                    for (int i = 0; i < GRID_SIZE; i++) for (int j = 0; j < GRID_SIZE; j++) begin
                        if (j < GRID_SIZE - i_matrix_cols) mat_arr[i_matrix_1][i][j] <= mat_arr[i_matrix_1][i][j + i_matrix_cols];
                        else mat_arr[i_matrix_1][i][j] <= 8'd0;
                    end
                end else if (i_relu_op) begin
                    if (matrix_signed[i_matrix_1]) begin
                        for (int i = 0; i < GRID_SIZE; i++) for (int j = 0; j < GRID_SIZE; j++) begin
                            if (mat_arr[i_matrix_1][i][j][7]) mat_arr[i_matrix_1][i][j] <= 8'd0;
                        end
                    end
                end else if (i_clamp_op) begin
                    for (int i = 0; i < GRID_SIZE; i++) for (int j = 0; j < GRID_SIZE; j++) begin
                        if (matrix_signed[i_matrix_1]) begin
                            if ($signed(mat_arr[i_matrix_1][i][j]) > $signed(i_clamp_max)) mat_arr[i_matrix_1][i][j] <= i_clamp_max;
                        end else begin
                            if (mat_arr[i_matrix_1][i][j] > i_clamp_max) mat_arr[i_matrix_1][i][j] <= i_clamp_max;
                        end
                    end
                end
            end
        endcase
    end
end

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) o_data_rd <= 8'd0;
    else if (i_data_read) o_data_rd <= mat_arr[i_matrix_1][i_matrix_rows][i_matrix_cols];
end

endmodule
