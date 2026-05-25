`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.03.2026 11:08:40
// Design Name: 
// Module Name: topk_cache
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

module topk_cache #(
    parameter K = 4,
    parameter IS_BID = 1 // Set to 1 for Bid Book (Descending), 0 for Ask Book (Ascending)
)(
    input  logic        clk,
    input  logic        reset,
    
    // Control Signals
    input  logic        insert_valid,
    input  logic        cancel_valid,
    input  logic        execute_valid,
    
    // Incoming Data
    input  logic [23:0] insert_price,
    input  logic [15:0] insert_quantity,
    input  logic [23:0] target_price,      // <--- RENAMED from cancel_price
    input  logic [15:0] execute_quantity,
    
    // Deep Storage (BRAM) Spillover Interface
    input  logic [23:0] bram_price,
    input  logic [15:0] bram_quantity,
    
    // Output (Top of the Book)
    output logic [23:0] best_price,
    output logic [15:0] best_quantity,
    output logic [23:0] price_input_bram,
    output logic [15:0] quantity_input_bram, 
    output logic        insert_bram_valid, // Signal to deep storage to store spillover
    output logic        cancel_bram_valid,
    output logic [23:0] least_price
);

    // -------------------------------------------------------------------------
    // 1. Hardware Register Arrays (The O(1) Cache)
    // -------------------------------------------------------------------------
    logic [23:0] price    [0:K-1];
    logic [15:0] quantity [0:K-1];
    logic [23:0] price_input_bram_reg;
    logic [15:0] qty_input_bram_reg;
  
    // Continuously output the absolute best price/quantity at index 0
    assign best_price    = price[0];
    assign best_quantity = quantity[0];
    assign price_input_bram   = price_input_bram_reg;
    assign quantity_input_bram = qty_input_bram_reg;
    assign least_price = price[K-1];

    // -------------------------------------------------------------------------
    // 2. Parallel Combinational Comparators
    // -------------------------------------------------------------------------
    logic [K-1:0] is_better;
    logic [K-1:0] is_match;

    always_comb begin
        for (int i = 0; i < K; i++) begin
            // Bid looks for HIGHER prices, Ask looks for LOWER prices
            if (IS_BID) begin
                is_better[i] = (insert_price > price[i]);
            end else begin
                is_better[i] = (insert_price < price[i]);
            end
            
            // Check if the current level matches the target price 
            is_match[i] = (target_price == price[i]);  // <--- UPDATED HERE
        end
    end

    // 3. O(1) Sequential Update Logic (Shift Registers)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            insert_bram_valid <= 1'b0;
            cancel_bram_valid <= 1'b0;
            price_input_bram_reg  <= 24'd0;
            qty_input_bram_reg    <= 16'd0;
            for (int i = 0; i < K; i++) begin
                if (IS_BID) begin
                    price[i] <= 24'd0; 
                end else begin
                    price[i] <= 24'hFFFFFF; 
                end
                quantity[i] <= 16'd0;
            end
        end else if (insert_valid) begin
            // --- FIX 1: EXACT MATCH AGGREGATION ---
            automatic logic exact_match_found;
            exact_match_found = 1'b0;
            insert_bram_valid <= 1'b0;
            cancel_bram_valid <= 1'b0;
            for (int i = 0; i < K; i++) begin
                if (insert_price == price[i]) begin
                    quantity[i] <= quantity[i] + insert_quantity;
                    exact_match_found = 1'b1;
                    insert_bram_valid <= 1'b0;
                end
            end
            
            // --- PARALLEL INSERTION (Shift Down only if NOT a match) ---
            if (!exact_match_found) begin
                automatic logic already_inserted;
                already_inserted = 1'b0;
                insert_bram_valid <= 1'b1;
                for (int i = 0; i < K; i++) begin
                    if (is_better[i] && !already_inserted) begin
                        price[i]    <= insert_price;
                        quantity[i] <= insert_quantity;
                        price_input_bram_reg  <= price[K-1];
                        qty_input_bram_reg    <= quantity[K-1];
                        already_inserted = 1'b1;
                    end else if (already_inserted) begin
                        price[i]    <= price[i-1];
                        quantity[i] <= quantity[i-1];
                    end
                end
              if (!already_inserted) begin
                  price_input_bram_reg <= insert_price;
                  qty_input_bram_reg   <= insert_quantity;
              end
               end else begin
                       insert_bram_valid <= 1'b0;
            end
            
        end else if (cancel_valid || execute_valid) begin
            // --- FIX 2: UNIFIED DECREASE & LAZY DELETION ---
            automatic logic shift_up;
            shift_up = 1'b0;
            insert_bram_valid <= 1'b0;
            cancel_bram_valid <= 1'b1;
            price_input_bram_reg<=target_price;
            qty_input_bram_reg<=execute_quantity;
            for (int i = 0; i < K; i++) begin
                if (is_match[i]) begin
                    // Shift up if it's a full cancel OR the execution zeroes out the level
                    if (cancel_valid || (quantity[i] <= execute_quantity)) begin
                        shift_up = 1'b1;
                    end else begin
                        cancel_bram_valid <= 1'b0;
                        quantity[i] <= quantity[i] - execute_quantity; // Partial fill
                    end
                end
                
                if (shift_up) begin
                    if (i == K - 1) begin
                        // Bottom of the cache pulls from BRAM
                        price[i]    <= bram_price;
                        quantity[i] <= bram_quantity;
                    end else begin
                        price[i]    <= price[i+1];
                        quantity[i] <= quantity[i+1];
                    end
                end
                end
        end
        else begin
            insert_bram_valid <= 1'b0;
            cancel_bram_valid <= 1'b0;
        end
    end
endmodule