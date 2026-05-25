`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 19.02.2026 19:29:11
// Design Name: 
// Module Name: order_book
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

`timescale 1ns / 1ps
import hft_types::*;

module order_book_top (
    input  logic        clk,
    input  logic        reset,
    
    // Inputs from Parser / Global Map
    input  logic        packet_valid,
    input  order_t      parsed_order,
    
    // Outputs to Trading Logic
    output logic [23:0] best_bid,
    output logic [15:0] best_bid_qty,
    output logic [23:0] best_ask,
    output logic [15:0] best_ask_qty,
    
    // Backpressure output to Central FIFO (Stall signal)
    output logic        fifo_full
);

    // Independent routing signals
    logic bid_valid, ask_valid;
    logic bid_busy, ask_busy;
    
    // The top module signals full/busy if either half is busy processing
    assign fifo_full = bid_busy | ask_busy;

    // Combinational Router: Direct packets to the correct book
    always_comb begin
        bid_valid = 0;
        ask_valid = 0;
        
        if (packet_valid) begin
            // Extract side directly from the struct!
            if (parsed_order.side == 8'h42) begin // Hex 42 is 'B' (Buy)
                bid_valid = 1;
            end else if (parsed_order.side == 8'h53) begin // Hex 53 is 'S' (Sell)
                ask_valid = 1;
            end
        end
    end

    // ---------------------------------------------------------
    // Instantiate the Bid Half (Buys - Seeks Maximum Price)
    // ---------------------------------------------------------
    order_book_half #(.IS_BID(1)) BID_BOOK (
        .clk(clk),
        .reset(reset),
        .packet_valid(bid_valid),
        .parsed_order_in(parsed_order),
        .busy(bid_busy),                 // FIXED: Was fifo_full
        .best_price(best_bid),
        .best_quantity(best_bid_qty)
    );

    // ---------------------------------------------------------
    // Instantiate the Ask Half (Sells - Seeks Minimum Price)
    // ---------------------------------------------------------
    order_book_half #(.IS_BID(0)) ASK_BOOK (
        .clk(clk),
        .reset(reset),
        .packet_valid(ask_valid),
        .parsed_order_in(parsed_order),
        .busy(ask_busy),                 // FIXED: Was fifo_full
        .best_price(best_ask),
        .best_quantity(best_ask_qty)
    );

endmodule