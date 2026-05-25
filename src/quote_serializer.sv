`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.03.2026 17:52:00
// Design Name: 
// Module Name: quote_serializer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module quote_serializer (
    input  logic        clk,
    input  logic        reset,
    
    // Quotes from Advanced Market Maker
    input  logic [23:0] final_ask,
    input  logic [23:0] final_bid,
    input  logic [15:0] final_ask_qty,
    input  logic [15:0] final_bid_qty,
    input  logic        final_ask_val,
    input  logic        final_bid_val,
    input  logic [3:0]  stock_id,
    input  logic [15:0] measured_latency,
    
    // Output to UART TX
    output logic [7:0]  tx_data,
    output logic        tx_valid
);

    logic [23:0] prev_ask, prev_bid;
    logic [15:0] latched_ask_qty, latched_bid_qty; 
    
    // NEW: Latches for Risk Brakes
    logic latched_ask_val, latched_bid_val; 
    
    logic [4:0]  tx_state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_state        <= 0;
            tx_valid        <= 0;
            tx_data         <= 0;
            prev_ask        <= 0;
            prev_bid        <= 0;
            latched_ask_qty <= 0;
            latched_bid_qty <= 0;
            latched_ask_val <= 0;
            latched_bid_val <= 0;
        end else begin
            
            // Trigger transmission if prices change and are valid
            if (tx_state == 0) begin
                tx_valid <= 0;
                if ((final_ask != prev_ask && final_ask_val) || 
                    (final_bid != prev_bid && final_bid_val)) begin
                    
                    prev_ask        <= final_ask;
                    prev_bid        <= final_bid;
                    latched_ask_qty <= final_ask_qty;
                    latched_bid_qty <= final_bid_qty;
                    
                    // Securely latch the validity from the AMM's Risk Brakes
                    latched_ask_val <= final_ask_val;
                    latched_bid_val <= final_bid_val;
                    
                    // --- SMART JUMP ---
                    // If Bid is valid, start at 1. If Bid is blocked by risk, skip to 13 (Ask).
                    if (final_bid_val) tx_state <= 1; 
                    else tx_state <= 13; 
                end
            end 
            else begin
                tx_valid <= 1;
                
                // Keep all your exact same byte formatting logic
                case (tx_state)
                
                    // --- BID ORDER PACKET (12 Bytes) ---
                    1:  tx_data <= 8'hAA;                 // SOF (Start of Frame)
                    2:  tx_data <= 8'h4F;                 // MsgType 'O' (Outbound Order)
                    3:  tx_data <= measured_latency[15:8]; // Latency High Byte
                    4:  tx_data <= measured_latency[7:0];  // Latency Low Byte
                    5:  tx_data <= 8'h42;                 // Side 'B' (Buy)
                    6:  tx_data <= final_bid[23:16];      // Price High Byte
                    7:  tx_data <= final_bid[15:8];       // Price Mid Byte
                    8:  tx_data <= final_bid[7:0];        // Price Low Byte
                    9:  tx_data <= latched_bid_qty[15:8]; // Quantity High Byte
                    10: tx_data <= latched_bid_qty[7:0];  // Quantity Low Byte
                    11: tx_data <= {stock_id, 4'h0};      // Flags: stock_id in upper 4 bits
                    12: tx_data <= 8'h55;                 // EOF (End of Frame)
                
                    // --- ASK ORDER PACKET (12 Bytes) ---
                    13: tx_data <= 8'hAA;                 // SOF (Start of Frame)
                    14: tx_data <= 8'h4F;                 // MsgType 'O' (Outbound Order)
                    15: tx_data <= measured_latency[15:8]; // Latency High Byte
                    16: tx_data <= measured_latency[7:0];  // Latency Low Byte
                    17: tx_data <= 8'h53;                 // Side 'S' (Sell)
                    18: tx_data <= final_ask[23:16];      // Price High Byte
                    19: tx_data <= final_ask[15:8];       // Price Mid Byte
                    20: tx_data <= final_ask[7:0];        // Price Low Byte
                    21: tx_data <= latched_ask_qty[15:8]; // Quantity High Byte
                    22: tx_data <= latched_ask_qty[7:0];  // Quantity Low Byte
                    23: tx_data <= {stock_id, 4'h0};      // Flags: stock_id in upper 4 bits
                    24: tx_data <= 8'h55;                 // EOF (End of Frame)
                
                endcase

                // --- SMART STATE PROGRESSION ---
                if (tx_state == 12) begin
                    // Bid packet finished. Should we send Ask?
                    if (latched_ask_val) tx_state <= 13; // Yes, continue to Ask
                    else tx_state <= 0;                  // No, Ask blocked by risk. Done.
                end else if (tx_state == 24) begin
                    tx_state <= 0; // Ask packet finished. Done.
                end else begin
                    tx_state <= tx_state + 1; // Normal increment
                end
                
            end
        end
    end
endmodule