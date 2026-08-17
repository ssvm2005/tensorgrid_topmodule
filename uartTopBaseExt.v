`timescale 1ns / 1ps

module uartTopBaseExt (
    input wire clr,                            // global reset input
    input wire clk,                            // global clock input
    input wire serIn,                          // serial data input
    output  serOut,                         // serial data output
    input [7:0] txData,                   // data byte to transmit
    input wire newTxData,                      // asserted to indicate new data byte for transmission
    output  txBusy,                         // transmitter busy flag
    output [7:0] rxData,                   // data byte received
    output  newRxData,                      // asserted to indicate new received data byte
    input wire [31:0] baudFreq,                // baud frequency inputx = ser.read(bytesWaiting)--baudFreq = 16 * baudRate / gcd(clkFreq, 16 * baudRate)--in this baudrate is 9600  gcd_value(25600)
    input wire [31:0] baudLimit,               //baudLimit = clkFreq / gcd(clkFreq, 16 * baudRate) - baudFreq
    output  baudClk                         // baud clock output
);
    // Signals declaration
    wire ce16;                   // clock enable at bit rate
    //wire newRxData;
    // Instantiate baudGenExt
    baudGenExt bg (
        .clr(clr),
        .clk(clk),
        .baudFreq(baudFreq),
        .baudLimit(baudLimit),
        .ce16(ce16)
    );

    // Instantiate uartTx
    uartTx ut (
        .clr(clr),
        .clk(clk),
        .ce16(ce16),
        .txData(txData),
        .newTxData(newTxData),
        .serOut(serOut),
        .txBusy(txBusy)
    );

    // Instantiate uartRx
    uartRx ur (
        .clr(clr),
        .clk(clk),
        .ce16(ce16),
        .serIn(serIn),
        .rxData(rxData),
        .newRxData(newRxData)
    );

    // Assign baudClk
    assign baudClk = ce16;

endmodule
