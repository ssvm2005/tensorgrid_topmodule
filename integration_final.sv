`timescale 1ns / 1ps

// function integer gcd(input integer a, b);
//     integer g, l, m;
//     g = b;
//     l = a;
//     if(a > b) begin
//         g = a;
//         l = b;
//     end
//     do begin
//         m = g % l;
//         g = l;
//         l = m;
//     end while(m != 0);
//     return g;
// endfunction

module integration_final #(
    parameter GRID_SIZE = 3,
    parameter UART_BAUD_RATE = 1000000,
    parameter CLK_FREQ = 48000000,
    // parameter BAUD_FREQ = 16*UART_BAUD_RATE/gcd(16*UART_BAUD_RATE, CLK_FREQ),
    // parameter BAUD_LIMIT = CLK_FREQ/gcd(16*UART_BAUD_RATE, CLK_FREQ) - BAUD_FREQ
    // use the above expressions to calculate the values of BAUD_FREQ and BAUD_LIMIT in your synthesis tool, as it may not support function calls in parameter definitions.
    parameter BAUD_FREQ = 1,
    parameter BAUD_LIMIT = 2
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic i_uart_rx,
    output logic o_uart_tx
);
    logic [7:0] uart_rx_data;
    logic uart_rx_new;
    logic [7:0] uart_tx_data;
    logic uart_tx_new;

    integration_minus_UART #(
        .GRID_SIZE(GRID_SIZE)
    ) integration_inst (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_uart_rx_data(uart_rx_data),
        .i_uart_rx_new(uart_rx_new),
        .o_uart_tx_data(uart_tx_data),
        .o_uart_tx_new(uart_tx_new)
    );

    uartTopBaseExt uart_inst(
        .clk(i_clk),
        .clr(!i_rst_n),
        .serIn(i_uart_rx),
        .serOut(o_uart_tx),
        .rxData(uart_rx_data),
        .newRxData(uart_rx_new),
        .txData(uart_tx_data),
        .newTxData(uart_tx_new),
        .baudFreq(BAUD_FREQ),
        .baudLimit(BAUD_LIMIT)
    );

endmodule
