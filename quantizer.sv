`timescale 1ns / 1ps

module quantizer(
    input logic i_clk,
    input logic i_rst_n,
    input logic signed [22:0] i_data,
    input logic [31:0] i_scale,
    input logic [7:0] i_zero_point,
    input logic [2:0] i_target_dtype, // 0, 6: int8, 1, 7: uint8, 2: int4, 3: uint4, 4: int2, 5: uint2
    output logic [7:0] o_quantized_data,
    output logic o_overflow
);
logic signed [47:0] scaled_data;
logic [7:0] shifts;
logic [7:0] zp_0;
logic [2:0] target_dtype_0;

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        scaled_data <= 48'sd0;
        shifts <= 8'd0;
        target_dtype_0 <= 3'd0;
        zp_0 <= 8'd0;
    end else begin
        target_dtype_0 <= i_target_dtype;
        zp_0 <= i_zero_point;
        shifts <= i_scale[30:23]; // Assuming scale is in float32
        scaled_data <= $signed(i_data) * $signed({1'b0, 1'b1, i_scale[22:0]});
    end
end

logic signed [79:0] extended_scaled_data;

always_comb begin
    if (shifts <= 134 && shifts >= 150 - 48) begin
        extended_scaled_data = $signed({scaled_data, 32'sd0}) >>> (150 - shifts); // Shift right by the exponent end
    end else begin
        extended_scaled_data = 0;
    end
end

logic signed [47:0] shifted_data;
logic [2:0] target_dtype_1;
logic [7:0] zp_1;
logic overflow_1;

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shifted_data <= 48'sd0;
        target_dtype_1 <= 3'd0;
        zp_1 <= 8'd0;
        overflow_1 <= 1'b0;
    end else begin
        target_dtype_1 <= target_dtype_0;
        zp_1 <= zp_0;
        overflow_1 <= scaled_data && (shifts > 134);
        if (!scaled_data) shifted_data <= 48'sd0;
        else begin
            if (shifts <= 134) begin
                if (shifts >= 150 - 48) shifted_data <= extended_scaled_data[79:32] + (extended_scaled_data[31] && (extended_scaled_data[32] || extended_scaled_data[30:0])); // Shift right by the exponent
                else shifted_data <= 48'sd0;
            end else shifted_data <= {(scaled_data[47]), {47{(!scaled_data[47])}}}; // Saturate to max/min
        end
    end
end

logic signed [47:0] added_data;
logic [2:0] target_dtype_2;
logic overflow_2;

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        added_data <= 48'sd0;
        target_dtype_2 <= 3'd0;
        overflow_2 <= 1'b0;
    end else begin
        if (overflow_1) added_data <= shifted_data; // If overflow, just pass the shifted data
        else begin
            if (target_dtype_1[0]) added_data <= shifted_data + $signed({40'd0, zp_1});
            else added_data <= shifted_data + $signed({{40{zp_1[7]}}, zp_1});
        end
        target_dtype_2 <= target_dtype_1;
        overflow_2 <= overflow_1;
    end
end

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_quantized_data <= 8'd0;
        o_overflow <= 1'b0;
    end else begin
        case (target_dtype_2)
            3'd0, 3'd6: begin // int8
                if (added_data > 48'sd127) o_quantized_data <= 8'h7F;
                else if (added_data < -48'sd128) o_quantized_data <= 8'h80;
                else o_quantized_data <= added_data[7:0];
                if (added_data > 48'sd127 || added_data < -48'sd128) o_overflow <= 1'b1;
                else o_overflow <= overflow_2;
            end
            3'd1, 3'd7: begin // uint8
                if (added_data > 48'sd255) o_quantized_data <= 8'hFF;
                else if (added_data < 48'sd0) o_quantized_data <= 8'h00;
                else o_quantized_data <= added_data[7:0];
                if (added_data > 48'sd255 || added_data < 48'sd0) o_overflow <= 1'b1;
                else o_overflow <= overflow_2;
            end
            3'd2: begin // int4
                if (added_data > 48'sd7) o_quantized_data <= 8'h07;
                else if (added_data < -48'sd8) o_quantized_data <= {{5{1'b1}}, 3'd0}; // -8 in 4-bit signed
                else o_quantized_data <= {{4{added_data[3]}}, added_data[3:0]};
                if (added_data > 48'sd7 || added_data < -48'sd8) o_overflow <= 1'b1;
                else o_overflow <= overflow_2;
            end
            3'd3: begin // uint4
                if (added_data > 48'sd15) o_quantized_data <= 8'h0F;
                else if (added_data < 48'sd0) o_quantized_data <= 8'h00;
                else o_quantized_data <= added_data[3:0];
                if (added_data > 48'sd15 || added_data < 48'sd0) o_overflow <= 1'b1;
                else o_overflow <= overflow_2;
            end
            3'd4: begin // int2
                if (added_data > 48'sd1) o_quantized_data <= 8'h01;
                else if (added_data < -48'sd2) o_quantized_data <= {{7{1'b1}}, 1'd0}; // -2 in 4-bit signed
                else o_quantized_data <= {{6{added_data[1]}}, added_data[1:0]};
                if (added_data > 48'sd1 || added_data < -48'sd2) o_overflow <= 1'b1;
                else o_overflow <= overflow_2;
            end
            3'd5: begin // uint2
                if (added_data > 48'sd3) o_quantized_data <= 8'h03;
                else if (added_data < 48'sd0) o_quantized_data <= 8'h00;
                else o_quantized_data <= added_data[1:0];
                if (added_data > 48'sd3 || added_data < 48'sd0) o_overflow <= 1'b1;
                else o_overflow <= overflow_2;
            end
        endcase
    end
end

endmodule