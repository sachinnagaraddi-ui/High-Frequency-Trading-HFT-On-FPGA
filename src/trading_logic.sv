`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.03.2026 14:47:43
// Design Name: 
// Module Name: trading_logic
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

module advanced_market_maker #(
    parameter signed [15:0] MAX_POS = 500,
    parameter signed [15:0] MIN_POS = -500
)(
    input  logic        clk,
    input  logic        reset,
    
    // Market Data from Order Book
    input  logic        best_bid_valid,
    input  logic        best_ask_valid,
    input  logic [23:0] best_bid,
    input  logic [23:0] best_ask,
    input  logic [15:0] best_bid_qty,
    input  logic [15:0] best_ask_qty,
    
    // Internal Execution Feed
    input  logic        fill_valid,
    input  logic        fill_side,     // 0 = Buy Fill, 1 = Sell Fill
    input  logic [15:0] fill_qty,
    
    // Final Output Quotes
    output logic [23:0] final_ask,
    output logic [23:0] final_bid,
    output logic [15:0] final_ask_qty,
    output logic [15:0] final_bid_qty,
    output logic        final_ask_val,
    output logic        final_bid_val
);

    // =====================================================================
    // STAGE 1: Market Analysis & Inventory Tracking 
    // =====================================================================
    // 1A. Zero-Latency Inventory Update (Mapped to LUTs, no DSP needed for 16-bit)
    logic signed [15:0] position;
    logic signed [15:0] nxt_position;
    
    assign nxt_position = fill_valid ? (fill_side ? (position - fill_qty) : (position + fill_qty)) : position;
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) position <= 0;
        else position <= nxt_position;
    end

    // 1B. Spread Calculation (Let Vivado use LUTs for speed, removed use_dsp)
    logic [24:0] spread;
    assign spread = best_ask - best_bid;

    // Stage 1 Pipeline Registers
    logic [23:0]        stg1_mid;
    logic [23:0]        stg1_margin;
    logic signed [15:0] stg1_skew;
    logic               stg1_bullish;
    logic               stg1_bearish;
    logic               stg1_valid;
    logic               stg1_block_buy;
    logic               stg1_block_sell;
    logic signed [15:0] stg1_nxt_position; 

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            stg1_valid       <= 0;
            stg1_mid         <= 0;
            stg1_margin      <= 0;
            stg1_skew        <= 0;
            stg1_bullish     <= 0;
            stg1_bearish     <= 0;
            stg1_block_buy   <= 0;
            stg1_block_sell  <= 0;
            stg1_nxt_position<= 0;
        end else begin
            stg1_valid <= (best_bid_valid && best_ask_valid && (best_ask > best_bid));
            
            stg1_mid    <= best_bid + (spread >> 1);
            stg1_margin <= (spread >> 2); 
            stg1_skew   <= nxt_position >>> 6; 
            
            stg1_bullish <= (best_bid_qty > (best_ask_qty << 2));
            stg1_bearish <= (best_ask_qty > (best_bid_qty << 2));
            
            stg1_block_buy  <= (nxt_position >= MAX_POS);
            stg1_block_sell <= (nxt_position <= MIN_POS);
            stg1_nxt_position <= nxt_position;
        end
    end

    // =====================================================================
    // STAGE 2: Quote Generation & Risk Gates (PIPELINED DSPs)
    // =====================================================================
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            final_ask     <= 0;
            final_bid     <= 0;
            final_ask_val <= 0;
            final_bid_val <= 0;
            final_ask_qty <= 0;
            final_bid_qty <= 0;
        end else if (stg1_valid) begin
            
            // 2A. Apply Market Price Conditions
            if (stg1_bullish) begin
                final_bid <= stg1_mid; 
                final_ask <= 24'hFFFFFF;
            end else if (stg1_bearish) begin
                final_ask <= stg1_mid; 
                final_bid <= 24'd0;
            end else begin
                // FIX: 3-Input Math is now INSIDE the clocked block! 
                // Vivado will absorb the final_ask/final_bid flip-flops directly into the DSP.
                final_ask <= $signed({1'b0, stg1_mid}) + $signed({1'b0, stg1_margin}) - stg1_skew;
                final_bid <= $signed({1'b0, stg1_mid}) - $signed({1'b0, stg1_margin}) - stg1_skew;
            end
            
            // 2B. Apply Hard Risk Gates
            final_bid_val <= !stg1_block_buy;
            final_ask_val <= !stg1_block_sell;

            // 2C. Dynamic Quantity Sizing
            if (stg1_nxt_position > 200) begin
                final_ask_qty <= 16'd200; 
                final_bid_qty <= 16'd50;  
            end else if (stg1_nxt_position < -200) begin
                final_ask_qty <= 16'd50;  
                final_bid_qty <= 16'd200; 
            end else begin
                final_ask_qty <= 16'd100; 
                final_bid_qty <= 16'd100; 
            end
            
        end else begin
            final_ask_val <= 0;
            final_bid_val <= 0;
        end
    end
endmodule