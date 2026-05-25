`timescale 1ns / 1ps
import hft_types::*;

module order_id_map (
    input  logic        clk,
    input  logic        reset,
    
    // Input from Parser
    input  logic        parse_valid_in,
    input  order_t      parsed_order_in,
    
    // Output to Demultiplexer / Order Books
    output logic        valid_out,
    output order_t      enriched_order_out
);

    // =====================================================================
    // 1. Pure BRAM Inference (65,536 depth x 40-bit width)
    // =====================================================================
    (* ram_style = "block" *) logic [39:0] global_id_bram [0:65535];
    
    logic [23:0] bram_read_price;
    logic [15:0] bram_read_qty;

    // Strict Simple Dual-Port Template
    always_ff @(posedge clk) begin
        // PORT A: Write (Only on ADD orders)
        if (parse_valid_in && (parsed_order_in.msg_type == 8'h4E || parsed_order_in.msg_type == 8'h41)) begin
            global_id_bram[parsed_order_in.token] <= {parsed_order_in.price, parsed_order_in.quantity};
        end
        
        // PORT B: Continuous Synchronous Read (1-cycle latency)
        // Unconditionally reading guarantees clean BRAM synthesis
        {bram_read_price, bram_read_qty} <= global_id_bram[parsed_order_in.token];
    end

    // =====================================================================
    // 2. Parallel 1-Cycle Pipeline for Control Signals
    // =====================================================================
    order_t pipeline_reg;
    logic   pipeline_valid;
    logic   is_add_reg;

    always_ff @(posedge clk) begin
        if (reset) begin
            pipeline_valid <= 0;
            is_add_reg     <= 0;
        end else begin
            // Shift the valid signal and the packet data by 1 cycle
            pipeline_valid <= parse_valid_in;
            pipeline_reg   <= parsed_order_in;
            
            // Remember if this packet was an ADD order so we know which price to use next cycle
            if (parsed_order_in.msg_type == 8'h4E || parsed_order_in.msg_type == 8'h41)
                is_add_reg <= 1'b1;
            else
                is_add_reg <= 1'b0;
        end
    end

    // =====================================================================
    // 3. Final Output Multiplexer
    // =====================================================================
    always_comb begin
        valid_out = pipeline_valid;
        
        // Pass through the standard fields that didn't change
        enriched_order_out.msg_type = pipeline_reg.msg_type;
        enriched_order_out.token    = pipeline_reg.token;
        enriched_order_out.side     = pipeline_reg.side;
        enriched_order_out.stock_id = pipeline_reg.stock_id;
        enriched_order_out.flags    = pipeline_reg.flags;

        // If it was an ADD order, use the new price/qty. 
        // If it was a CANCEL/TRADE, use the deeply stored BRAM price/qty.
        if (is_add_reg) begin
            enriched_order_out.price    = pipeline_reg.price;
            enriched_order_out.quantity = pipeline_reg.quantity;
        end else begin
            enriched_order_out.price    = bram_read_price;
            enriched_order_out.quantity = bram_read_qty;
        end
    end

endmodule