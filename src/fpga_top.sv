`timescale 1ns / 1ps

module fpga_top (
    input  logic clk,     // 100MHz clock from ZedBoard Pin Y9
    input  logic reset,   // BTNC Center Button
    input  logic rx,      // Pmod JA3 (Y10)
    output logic tx,      // Pmod JA2 (AA11)
    output logic [7:0] led // 8 User LEDs
);

    // Stream Interconnects between Network Card and Core
    logic [7:0] rx_stream_data;
    logic rx_stream_valid;
    
    logic [7:0] tx_stream_data;
    logic tx_stream_valid;

    // --- 1. UART Interface (Physical Layer) ---
    uart_interface UART_INTERFACE (
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .tx(tx),
        .rx_data(rx_stream_data),
        .rx_valid(rx_stream_valid),
        .tx_data(tx_stream_data),
        .tx_valid(tx_stream_valid)
    );

    // --- 2. HFT Core (Application Layer) ---
    hft_core HFT_CORE (
        .clk(clk),
        .reset(reset),
        .rx_data(rx_stream_data),
        .rx_valid(rx_stream_valid),
        .tx_data(tx_stream_data),
        .tx_valid(tx_stream_valid),
        .debug_led(led)
    );

endmodule