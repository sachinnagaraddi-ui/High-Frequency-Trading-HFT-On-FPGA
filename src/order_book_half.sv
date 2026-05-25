`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.03.2026 12:24:50
// Design Name: 
// Module Name: order_book_half
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

import hft_types::*;

module order_book_half #(
    parameter IS_BID = 1
)(
    input  logic        clk,
    input  logic        reset,
    
    // From Top-Level Router (Demultiplexer / Central FIFO)
    input  logic        packet_valid,
    input  order_t      parsed_order_in,
    output logic        busy, // Sends backpressure to the central FIFO
    
    // Output to Trading Logic
    output logic [23:0] best_price,
    output logic [15:0] best_quantity
);

    // ---------------------------------------------------------
    // 1. Core Data Structures (Circular BRAM & Top-K)
    // ---------------------------------------------------------
    logic insert_valid, cancel_valid,insert_bram_valid, cancel_bram_valid;
    logic [23:0] active_price;
    logic [15:0] active_qty;
    
    logic        bram_busy;
  logic [23:0] bram_spill_price,cache_bottom_price, price_input_bram;
  logic [15:0] bram_spill_qty,quantity_input_bram;

    circular_sparse_bram #(.IS_BID(IS_BID)) BRAM_BOOK (
        .clk(clk), 
        .reset(reset),
        .insert_valid(insert_bram_valid), 
        .cancel_valid(cancel_bram_valid),
        .price(price_input_bram), 
        .quantity(quantity_input_bram),
        .cache_bottom_price(cache_bottom_price),
        .bram_price_out(bram_spill_price), 
        .bram_qty_out(bram_spill_qty),
        .busy(bram_busy)
    );

    topk_cache #(.K(4), .IS_BID(IS_BID)) TOP_K_CACHE (
        .clk(clk), 
        .reset(reset),
        .insert_valid(insert_valid), 
        .cancel_valid(cancel_valid), 
        .execute_valid(1'b0),
        .insert_price(active_price), 
        .insert_quantity(active_qty),
        .target_price(active_price), 
        .execute_quantity(16'd0), // You routed active_qty above; leaving as you had it
        .bram_price(bram_spill_price), 
        .bram_quantity(bram_spill_qty),
        .best_price(best_price), 
        .best_quantity(best_quantity),
      .least_price(cache_bottom_price),
      .price_input_bram(price_input_bram),
      .quantity_input_bram(quantity_input_bram),
      .insert_bram_valid(insert_bram_valid),
      .cancel_bram_valid(cancel_bram_valid)
    );

    // ---------------------------------------------------------
    // 2. Combinational Packet Routing
    // ---------------------------------------------------------
    
    // Bubble up the busy signal so the central FIFO knows to stall
    assign busy = bram_busy; 

    always_comb begin
        insert_valid = 0;
        cancel_valid = 0;
        
        // Because of the Global ID Map, we can trust the price directly from the struct!
        active_price = parsed_order_in.price;
        active_qty   = parsed_order_in.quantity;

        // Only process if we have a valid packet and the BRAM isn't busy shifting
        if (packet_valid && !bram_busy) begin
            
            // 'N' = 0x4E or 'A' = 0x41 (Add Order)
            if (parsed_order_in.msg_type == 8'h4E || parsed_order_in.msg_type == 8'h41) begin
                insert_valid = 1;
            end 
            // 'X' = 0x58 (Cancel) or 'T' = 0x54 / 'E' = 0x45 (Execute/Trade)
            else if (parsed_order_in.msg_type == 8'h58 || 
                     parsed_order_in.msg_type == 8'h54 || 
                     parsed_order_in.msg_type == 8'h45) begin
                cancel_valid = 1;
            end
        end
    end

endmodule