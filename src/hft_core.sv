`timescale 1ns / 1ps
import hft_types::*;

module hft_core (
    input  logic       clk,
    input  logic       reset,
    
    // Interface with UART
    input  logic [7:0] rx_data,
    input  logic       rx_valid,
    output logic [7:0] tx_data,
    output logic       tx_valid,
    
    // Debug
    output logic [7:0] debug_led
);

    // =====================================================================
    // 1. Parser Interconnects
    // =====================================================================
    logic [95:0] packet;
    logic        comp_packet;
    logic [7:0]  msg_type, side;
    logic [3:0]  stock_id, flags;
    logic [15:0] token, quantity;
    logic [23:0] price;
    logic        parse_valid;

    packet_assembler ASSEMBLER (
        .clk(clk), .reset(reset),
        .uart_byte(rx_data), .rx_data_valid(rx_valid),
        .packet(packet), .packet_valid(comp_packet)
    );

    parsing PARSER (
        .clk(clk), .reset(reset),
        .packet_in(packet), .packet_valid_in(comp_packet),
        .msg_type(msg_type), .side(side), .token(token),
        .quantity(quantity), .price(price), .stock_id(stock_id),
        .flags(flags), .parse_valid(parse_valid)
    );

    // =====================================================================
    // 1.5 GLOBAL ORDER ID MAP
    // =====================================================================
    order_t parsed_order;
    order_t enriched_order;
    logic   enriched_valid;

    always_comb begin
        parsed_order.msg_type = msg_type;
        parsed_order.stock_id = stock_id;
        parsed_order.side     = side;
        parsed_order.token    = token;
        parsed_order.price    = price;
        parsed_order.quantity = quantity;
    end

    order_id_map GLOBAL_MAP (
        .clk(clk), .reset(reset),
        .parse_valid_in(parse_valid), .parsed_order_in(parsed_order),
        .valid_out(enriched_valid), .enriched_order_out(enriched_order)
    );

    // =====================================================================
    // 1.7 CENTRAL SYNCHRONOUS FIFO & TIMESTAMP TRACKING (Burst Absorption)
    // =====================================================================
    logic fifo_empty, central_fifo_full;
    logic fifo_rd_en;
    order_t fifo_order;

    // --- NEW: Free-running Global Timer ---
    logic [31:0] global_timer;
    logic [31:0] ingress_timestamp;
    logic [31:0] fifo_timestamp;

    always_ff @(posedge clk) begin
        if (reset) global_timer <= 0;
        else global_timer <= global_timer + 1;
    end

    // Capture the time the packet finished parsing
    always_ff @(posedge clk) begin
        if (parse_valid) ingress_timestamp <= global_timer;
    end

    sync_fifo #(.WIDTH(80), .DEPTH(512)) CENTRAL_FIFO (
        .clk(clk), .reset(reset),
        .wr_en(enriched_valid), .din(enriched_order), .full(central_fifo_full),
        .rd_en(fifo_rd_en), .dout(fifo_order), .empty(fifo_empty)
    );

    // --- NEW: Parallel FIFO for Timestamps ---
    sync_fifo_timestamp #(.WIDTH(32), .DEPTH(512)) TIMESTAMP_FIFO (
        .clk(clk), .reset(reset),
        .wr_en(enriched_valid), .din(ingress_timestamp), .full(), // Bounds matching CENTRAL_FIFO
        .rd_en(fifo_rd_en), .dout(fifo_timestamp), .empty()
    );

    // =====================================================================
    // 1.8 DEMUX PIPELINE REGISTER
    // =====================================================================
    order_t parsed_order_array [0:3];
    logic [3:0] ob_enable;
    
    logic pipe_is_fill;
    logic pipe_fill_side_val;
    logic [15:0] pipe_fill_qty;
    logic pipe_valid;
    logic [3:0] pipe_target_stock;

    // --- NEW: Timestamp routing registers ---
    logic [31:0] pipe_timestamp;
    logic [31:0] stock_processing_timestamp [0:3];

    logic [23:0] best_bid [0:3];
    logic [23:0] best_ask [0:3];
    logic [15:0] best_bid_qty [0:3];
    logic [15:0] best_ask_qty [0:3];
    logic fifo_full [0:3]; 

    logic active_ob_busy;
    assign active_ob_busy = (fifo_order.stock_id < 4) ? 
        (fifo_full[fifo_order.stock_id] || (pipe_valid && pipe_target_stock == fifo_order.stock_id)) : 1'b0;

    assign fifo_rd_en = !fifo_empty && !active_ob_busy;

    always_ff @(posedge clk) begin
        if (reset) begin
            for (int j = 0; j < 4; j++) begin
                ob_enable[j] <= 1'b0;
                parsed_order_array[j] <= '0;
                stock_processing_timestamp[j] <= 0;
            end
            pipe_is_fill <= 0;
            pipe_fill_side_val <= 0;
            pipe_fill_qty <= 0;
            pipe_valid <= 0;
            pipe_target_stock <= 0;
            pipe_timestamp <= 0;
        end else begin
            // Default inactive state
            for (int j = 0; j < 4; j++) begin
                ob_enable[j] <= 1'b0;
                parsed_order_array[j] <= '0;
            end
            pipe_valid <= 0;
            pipe_is_fill <= 0;

            if (fifo_rd_en && fifo_order.stock_id < 4) begin
                // Route popped data into flip-flops
                ob_enable[fifo_order.stock_id] <= 1'b1;
                parsed_order_array[fifo_order.stock_id] <= fifo_order;
                pipe_valid <= 1'b1;
                pipe_target_stock <= fifo_order.stock_id;
                
                // Track timestamps out of the FIFO
                pipe_timestamp <= fifo_timestamp;
                
                if (fifo_order.msg_type == 8'h54 || fifo_order.msg_type == 8'h45) begin
                    pipe_is_fill <= 1'b1;
                    pipe_fill_side_val <= (fifo_order.side == 8'h42); 
                    pipe_fill_qty <= fifo_order.quantity;
                end
            end

            // Assign the tracked timestamp to the specific stock
            if (pipe_valid && pipe_target_stock < 4) begin
                stock_processing_timestamp[pipe_target_stock] <= pipe_timestamp;
            end
        end
    end


    // =====================================================================
    // 2. Multi-Stock Routing & Order Books (4 Stocks)
    // =====================================================================
    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : ORDER_BOOK_ARRAY
            order_book_top ORDER_BOOK (
                .clk(clk), .reset(reset),
                .packet_valid(ob_enable[i]), 
                .parsed_order(parsed_order_array[i]), 
                .best_bid(best_bid[i]), .best_bid_qty(best_bid_qty[i]),
                .best_ask(best_ask[i]), .best_ask_qty(best_ask_qty[i]),
                .fifo_full(fifo_full[i])
            );
        end
    endgenerate

    // =====================================================================
    // 3. Output Multiplexer (Tracking the Active Stock)
    // =====================================================================
    logic [1:0] active_stock;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            active_stock <= 2'd0;
        end else if (pipe_valid) begin // Matches pipeline timing perfectly
            active_stock <= pipe_target_stock[1:0];
        end
    end

    logic [23:0] active_best_bid, active_best_ask;
    logic [15:0] active_best_bid_qty, active_best_ask_qty;

    assign active_best_bid     = best_bid[active_stock];
    assign active_best_ask     = best_ask[active_stock];
    assign active_best_bid_qty = best_bid_qty[active_stock];
    assign active_best_ask_qty = best_ask_qty[active_stock];

    // =====================================================================
    // 5. Advanced Market Maker Instantiation
    // =====================================================================
    logic [23:0] final_ask, final_bid;
    logic        final_ask_val, final_bid_val;
    logic [15:0] mm_ask_qty, mm_bid_qty;

    advanced_market_maker #(
        .MAX_POS(500), .MIN_POS(-500)
    ) AMM (
        .clk(clk), .reset(reset),
        .best_bid_valid(active_best_bid > 0),
        .best_ask_valid(active_best_ask > 0 && active_best_ask < 24'hFFFFFF),
        .best_bid(active_best_bid), .best_ask(active_best_ask),
        .best_bid_qty(active_best_bid_qty), .best_ask_qty(active_best_ask_qty),
        
        // Feed the pipelined execution signals
        .fill_valid(pipe_is_fill), .fill_side(pipe_fill_side_val), .fill_qty(pipe_fill_qty), 
        
        .final_ask(final_ask), .final_bid(final_bid),
        .final_ask_val(final_ask_val), .final_bid_val(final_bid_val),
        .final_ask_qty(mm_ask_qty), .final_bid_qty(mm_bid_qty)
    );

    // =====================================================================
    // 6. LATENCY CALCULATION (Dual-Path Sync Logic)
    // =====================================================================
    logic [3:0] ob_enable_q;
    logic [3:0] ob_was_busy;
    logic [3:0] ob_done_pulse;

    always_ff @(posedge clk) begin
        if (reset) begin
            ob_enable_q   <= 0;
            ob_was_busy   <= 0;
            ob_done_pulse <= 0;
        end else begin
            // Track what was sent to the order book 1 cycle ago
            ob_enable_q <= ob_enable; 

            for (int i = 0; i < 4; i++) begin
                ob_was_busy[i] <= fifo_full[i]; // Track BRAM active state

                // A packet officially finishes processing if:
                // Path A: It triggered BRAM, and BRAM just finished (falling edge)
                if (ob_was_busy[i] && !fifo_full[i]) begin
                    ob_done_pulse[i] <= 1'b1;
                end 
                // Path B: It was sent to the book, but BRAM never woke up! (Top-K Instant Hit)
                else if (ob_enable_q[i] && !fifo_full[i]) begin
                    ob_done_pulse[i] <= 1'b1;
                end 
                else begin
                    ob_done_pulse[i] <= 1'b0;
                end
            end
        end
    end

    // The AMM takes exactly 2 clock cycles after the Order Book finishes.
    logic [31:0] amm_stage1_ts, amm_stage2_ts;
    logic amm_stage1_valid, amm_stage2_valid;

    always_ff @(posedge clk) begin
        if (reset) begin
            amm_stage1_valid <= 0;
            amm_stage2_valid <= 0;
            amm_stage1_ts    <= 0;
            amm_stage2_ts    <= 0;
        end else begin
            amm_stage1_valid <= 1'b0; // Default drop
            
            // FIX: Safely extract the exact timestamp from the array index!
            if (ob_done_pulse[0]) begin
                amm_stage1_ts    <= stock_processing_timestamp[0];
                amm_stage1_valid <= 1'b1;
            end else if (ob_done_pulse[1]) begin
                amm_stage1_ts    <= stock_processing_timestamp[1];
                amm_stage1_valid <= 1'b1;
            end else if (ob_done_pulse[2]) begin
                amm_stage1_ts    <= stock_processing_timestamp[2];
                amm_stage1_valid <= 1'b1;
            end else if (ob_done_pulse[3]) begin
                amm_stage1_ts    <= stock_processing_timestamp[3];
                amm_stage1_valid <= 1'b1;
            end

            // Shift through AMM computational delay
            amm_stage2_ts    <= amm_stage1_ts;
            amm_stage2_valid <= amm_stage1_valid;
        end
    end

    logic [15:0] measured_latency;

    always_ff @(posedge clk) begin
        if (reset) begin
            measured_latency <= 0;
        end else if (amm_stage2_valid) begin
            // EXACT End-to-End Latency calculation!
            measured_latency <= (global_timer - amm_stage2_ts); 
        end
    end

    // =====================================================================
    // 7. Order Generation (UART TX Serializer)
    // =====================================================================
    quote_serializer OUTBOUND_ORDERS (
        .clk(clk), .reset(reset),
        .final_ask(final_ask), .final_bid(final_bid),
        .final_ask_val(final_ask_val), .final_bid_val(final_bid_val),
        .stock_id({2'b00, active_stock}),
        .tx_data(tx_data), .tx_valid(tx_valid),
        .final_ask_qty(mm_ask_qty), .final_bid_qty(mm_bid_qty),
        .measured_latency(measured_latency) // Cleanly fed into the serializer
    );
    
    // =====================================================================
    // 8. Debug LEDs
    // =====================================================================
    always_ff @(posedge clk) begin
        if (reset) debug_led <= 0;
        else  begin
            debug_led[0] <= (active_best_bid > 0);
            debug_led[1] <= (active_best_ask > 0 && active_best_ask < 24'hFFFFFF);
            debug_led[2] <= final_bid_val;
            debug_led[3] <= final_ask_val;
            debug_led[4] <= parse_valid;
            debug_led[7:5] <= 3'b0;
        end
    end
    
    // ILA:
    ila_0 ila_inst (
        .clk(clk), // input wire clk
    
        .probe0(tx_valid), // input wire [0:0]  probe0  
        .probe1(rx_valid), // input wire [0:0]  probe1 
        .probe2(comp_packet), // input wire [0:0]  probe2 
        .probe3(parse_valid), // input wire [0:0]  probe3 
        .probe4(1'b0), // input wire [0:0]  probe4 
        .probe5(fifo_full[0]), // input wire [0:0]  probe5 
        .probe6(1'b0), // input wire [0:0]  probe6 
        .probe7(latency_done) // input wire [0:0]  probe7
    );
    
endmodule