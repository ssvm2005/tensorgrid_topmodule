`timescale 1ns / 1ps

module int_MAC(
    input logic i_clk,
    input logic i_rst_n,
    input logic i_valid,
    input logic signed [8:0] i_a,
    input logic signed [8:0] i_b,
    output logic o_valid,
    output logic signed [22:0] o_result,
    output logic o_overflow
);
    logic signed [17:0] product;
    logic valid_0;
    // logic [7:0] magn_a, magn_b;
    // logic signed [16:0] product_0;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            product <= 18'sd0;
            valid_0 <= 1'b0;
        end else begin
            if (i_valid) product <= $signed(i_a) * $signed(i_b);
            valid_0 <= i_valid;
        end
    end

    logic signed [23:0] extended_result; // For overflow detection
    logic signed [22:0] result_reg;
    logic overflow;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            result_reg <= 23'sd0;
            o_overflow <= 1'b0;
            o_valid <= 1'b0;
        end else begin
            if (valid_0 && !o_overflow) result_reg <= extended_result[22:0]; // Store the lower 23 bits of the extended result
            if (valid_0 && !o_overflow) o_overflow <= overflow;
            o_valid <= valid_0 && !o_overflow; // Output valid only if there is no overflow
        end
    end

    assign extended_result = $signed({result_reg[22], result_reg}) + $signed({{6{product[17]}}, product});
    assign overflow = extended_result[23] != extended_result[22]; // Check if the sign bit has changed
    assign o_result = result_reg;

endmodule
