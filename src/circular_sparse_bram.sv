`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.03.2026 12:33:52
// Design Name: 
// Module Name: circular_sparse_bram
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


//module circular_sparse_bram #(
//    parameter IS_BID = 1
//)(
//    input  logic        clk,
//    input  logic        reset,

//    // Inputs from Hash Map / Control FSM
//    input  logic        insert_valid,
//    input  logic        cancel_valid,
//    input  logic [23:0] price,
//    input  logic [15:0] quantity,

//    // Top-K Cache Spillover Interface
//    input  logic [23:0] cache_bottom_price, 
//    output logic [23:0] bram_price_out,
//    output logic [15:0] bram_qty_out,
//    output logic        busy
//);

//    // --- 1. Memory and Core State ---
//    (* ram_style = "block" *) logic [15:0] qty_bram [0:1023];

//    logic [1023:0] price_mask;
//    logic [23:0]   curr_center;
//    logic [9:0]    base_ptr;

//    typedef enum logic [2:0] {
//        IDLE,
//        SHIFT_UP,
//        SHIFT_DOWN,
//        MODIFY_READ,
//        MODIFY_WAIT,
//        MODIFY_WRITE
//    } state_t;
//    state_t state;

//    logic        is_insert_op;
//    logic [15:0] pending_qty;
//    logic [9:0]  target_idx;

//    // Port A: FSM Read-Modify-Write
//    logic        we_A;
//    logic [9:0]  addr_A;
//    logic [15:0] din_A;
//    logic [15:0] dout_A;

//    always_ff @(posedge clk) begin
//        if (we_A) qty_bram[addr_A] <= din_A;
//        dout_A <= qty_bram[addr_A];
//    end

//    // --- 2. Dynamic Masking & Priority Encoder for Port B ---
    
//    // Stage 1 & 2 Registers
//    logic [9:0]    safe_limit_idx_reg;
//    logic [1023:0] active_mask_reg;

//    // ----------------------------------------------------------------
//    // Stage 1: 24-bit Arithmetic and Clamping (Combinational -> FF)
//    // ----------------------------------------------------------------
//    // NEW FIX: Force 24-bit Add/Sub into DSP blocks
//    (* use_dsp = "yes" *) logic signed [24:0] cache_diff;
//    (* use_dsp = "yes" *) logic signed [24:0] limit_idx_signed;

//    assign cache_diff = $signed({1'b0, cache_bottom_price}) - $signed({1'b0, curr_center});
//    assign limit_idx_signed = cache_diff + 512;

//    always_ff @(posedge clk) begin
//        if (reset) begin
//            safe_limit_idx_reg <= 10'd0;
//        end else begin
//            // Math and clamping happen here, safely captured by a register
//            if (limit_idx_signed <= 0)
//                safe_limit_idx_reg <= 10'd0;
//            else if (limit_idx_signed >= 1023)
//                safe_limit_idx_reg <= 10'd1023;
//            else
//                safe_limit_idx_reg <= limit_idx_signed[9:0];
//        end
//    end

//    // ----------------------------------------------------------------
//    // Stage 2: Hierarchical Mask Generation (Combinational -> FF)
//    // ----------------------------------------------------------------
//    logic [4:0] block_limit;
//    logic [4:0] local_limit;
    
//    // Driven entirely by the Stage 1 register
//    assign block_limit = safe_limit_idx_reg[9:5];
//    assign local_limit = safe_limit_idx_reg[4:0];

//    logic [31:0] local_bid_mask;
//    logic [31:0] local_ask_mask;
//    assign local_bid_mask = (32'b1 << local_limit) - 32'd1;
//    assign local_ask_mask = (local_limit == 5'd31) ? 32'd0 : ~((32'b1 << (local_limit + 5'd1)) - 32'd1);

//    logic [1023:0] active_mask_comb;

//    always_comb begin
//        for (int i = 0; i < 32; i++) begin
//            if (IS_BID) begin
//                if (cache_bottom_price == 24'd0 || safe_limit_idx_reg >= 1023)
//                    active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32];
//                else if (safe_limit_idx_reg == 0)
//                    active_mask_comb[i*32 +: 32] = 32'd0;
//                else begin
//                    if (i < block_limit)
//                        active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32];
//                    else if (i == block_limit)
//                        active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32] & local_bid_mask;
//                    else
//                        active_mask_comb[i*32 +: 32] = 32'd0;
//                end
//            end else begin
//                // Ask logic
//                if (cache_bottom_price == 24'hFFFFFF || safe_limit_idx_reg == 0)
//                    active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32];
//                else if (safe_limit_idx_reg >= 1023)
//                    active_mask_comb[i*32 +: 32] = 32'd0;
//                else begin
//                    if (i > block_limit)
//                        active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32];
//                    else if (i == block_limit)
//                        active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32] & local_ask_mask;
//                    else
//                        active_mask_comb[i*32 +: 32] = 32'd0;
//                end
//            end
//        end
//    end

//    // Stage 2 Pipeline Register
//    always_ff @(posedge clk) begin
//        if (reset) active_mask_reg <= 1024'd0;
//        else       active_mask_reg <= active_mask_comb;
//    end

//    // ----------------------------------------------------------------
//    // Stage 3: Priority Encoder 
//    // ----------------------------------------------------------------
//    logic [9:0] best_index;
//    logic       encoder_valid;

//    hierarchical_encoder #(.IS_BID(IS_BID)) ENCODER (
//        .clk(clk),
//        .mask_in(active_mask_reg), 
//        .best_index(best_index),
//        .valid(encoder_valid)
//    );

//    // Port B: Continuous Read for Top-K Cache
//    logic [9:0] addr_B;
//    assign addr_B = (best_index + base_ptr) & 1023;

//    always_ff @(posedge clk) begin
//        bram_qty_out <= qty_bram[addr_B];
//    end

//    // Reverse calculate price from index
//    assign bram_price_out = encoder_valid ? (curr_center - 512 + best_index) : (IS_BID ? 24'd0 : 24'hFFFFFF);

//    // --- 3. Main Circular Buffer FSM ---
//    logic signed [24:0] price_diff;
//    logic signed [24:0] target_center_up;
//    logic signed [24:0] target_center_down;
    
//    assign price_diff         = $signed({1'b0, price}) - $signed({1'b0, curr_center});
//    assign target_center_up   = $signed({1'b0, price}) - 511;
//    assign target_center_down = $signed({1'b0, price}) + 512;

//    always_ff @(posedge clk) begin
//        if (reset) begin
//            state       <= IDLE;
//            busy        <= 0;
//            price_mask  <= 0;
//            curr_center <= 0;
//            base_ptr    <= 0;
//            we_A        <= 0;
//        end else begin
//            case (state)
//                IDLE: begin
//                    we_A <= 0;
//                    if (insert_valid || cancel_valid) begin
//                        busy <= 1;
//                        is_insert_op <= insert_valid;
//                        pending_qty  <= quantity;

//                        // First order initialization
//                        if (curr_center == 0 && price_mask == 0) begin
//                            curr_center <= price;
//                            target_idx  <= 512;
//                            state       <= MODIFY_READ;
//                        end else if (price_diff > 511) begin
//                            if (price_diff > 1535) begin // Jump optimization: skip huge loops
//                                curr_center <= target_center_up[23:0];
//                                price_mask  <= 0;
//                                target_idx  <= 1023;
//                                state       <= MODIFY_READ;
//                            end else begin
//                                state <= SHIFT_UP;
//                            end
//                        end else if (price_diff < -512) begin
//                            if (price_diff < -1536) begin // Jump optimization
//                                curr_center <= target_center_down[23:0];
//                                price_mask  <= 0;
//                                target_idx  <= 0;
//                                state       <= MODIFY_READ;
//                            end else begin
//                                state <= SHIFT_DOWN;
//                            end
//                        end else begin
//                            target_idx <= price_diff[9:0] + 512;
//                            state      <= MODIFY_READ;
//                        end
//                    end else begin
//                        busy <= 0;
//                    end
//                end

//                SHIFT_UP: begin
//                    if ($signed({1'b0, curr_center}) < target_center_up) begin
//                        curr_center <= curr_center + 1;
//                        base_ptr    <= (base_ptr + 1) & 1023;
//                        price_mask  <= {1'b0, price_mask[1023:1]};
//                    end else begin
//                        target_idx <= 1023;
//                        state      <= MODIFY_READ;
//                    end
//                end

//                SHIFT_DOWN: begin
//                    if ($signed({1'b0, curr_center}) > target_center_down) begin
//                        curr_center <= curr_center - 1;
//                        base_ptr    <= (base_ptr - 1) & 1023;
//                        price_mask  <= {price_mask[1022:0], 1'b0};
//                    end else begin
//                        target_idx <= 0;
//                        state      <= MODIFY_READ;
//                    end
//                end

//                MODIFY_READ: begin
//                    addr_A <= (target_idx + base_ptr) & 1023;
//                    we_A   <= 0;
//                    state  <= MODIFY_WAIT; // 1 cycle wait for BRAM data
//                end

//                MODIFY_WAIT: begin
//                    state <= MODIFY_WRITE;
//                end

//                MODIFY_WRITE: begin
//                    we_A   <= 1;
//                    addr_A <= addr_A; // Hold address
//                    if (is_insert_op) begin
//                        // If price_mask is 0, ignore BRAM garbage data!
//                        din_A <= (price_mask[target_idx] ? dout_A : 0) + pending_qty;
//                        price_mask[target_idx] <= 1'b1;
//                    end else begin
//                        if (price_mask[target_idx]) begin
//                            if (dout_A <= pending_qty) begin
//                                din_A <= 0;
//                                price_mask[target_idx] <= 1'b0; // Lazy delete
//                            end else begin
//                                din_A <= dout_A - pending_qty;
//                            end
//                        end
//                    end
//                    state <= IDLE;
//                    busy  <= 0; 
//                end

//                default: state <= IDLE;
//            endcase
//        end
//    end
//endmodule

module circular_sparse_bram #(
    parameter IS_BID = 1
)(
    input  logic        clk,
    input  logic        reset,

//    // Inputs from Hash Map / Control FSM
    input  logic        insert_valid,
    input  logic        cancel_valid,
    input  logic [23:0] price,
    input  logic [15:0] quantity,

//    // Top-K Cache Spillover Interface
    input  logic [23:0] cache_bottom_price, 
    output logic [23:0] bram_price_out,
    output logic [15:0] bram_qty_out,
    output logic        busy
);

//    // --- 1. Memory and Core State ---
    (* ram_style = "block" *) logic [15:0] qty_bram [0:511];

    logic [511:0] price_mask;
    logic [23:0]   curr_center;
    logic [8:0]    base_ptr;

    typedef enum logic [2:0] {
        IDLE,
        SHIFT_UP,
        SHIFT_DOWN,
        MODIFY_READ,
        MODIFY_WAIT,
        MODIFY_WRITE
    } state_t;
    state_t state;

    logic        is_insert_op;
    logic [15:0] pending_qty;
    logic [8:0]  target_idx;

//    // Port A: FSM Read-Modify-Write
    logic        we_A;
    logic [8:0]  addr_A;
    logic [15:0] din_A;
    logic [15:0] dout_A;

    always_ff @(posedge clk) begin
        if (we_A) qty_bram[addr_A] <= din_A;
        else dout_A <= qty_bram[addr_A];
    end

//    // --- 2. Dynamic Masking & Priority Encoder for Port B ---
    
//    // Stage 1 & 2 Registers
    logic [8:0]    safe_limit_idx_reg;
    logic [511:0] active_mask_reg;

//    // ----------------------------------------------------------------
//    // Stage 1: 24-bit Arithmetic and Clamping (Combinational -> FF)
//    // ----------------------------------------------------------------
//    // NEW FIX: Force 24-bit Add/Sub into DSP blocks
    (* use_dsp = "yes" *) logic signed [24:0] cache_diff;
    (* use_dsp = "yes" *) logic signed [24:0] limit_idx_signed;

    assign cache_diff = $signed({1'b0, cache_bottom_price}) - $signed({1'b0, curr_center});
    assign limit_idx_signed = cache_diff + 256;

    always_ff @(posedge clk) begin
        if (reset) begin
            safe_limit_idx_reg <= 9'd0;
        end else begin
//            // Math and clamping happen here, safely captured by a register
            if (limit_idx_signed <= 0)
                safe_limit_idx_reg <= 9'd0;
            else if (limit_idx_signed >= 511)
                safe_limit_idx_reg <= 9'd511;
            else
                safe_limit_idx_reg <= limit_idx_signed[8:0];
        end
    end

//    // ----------------------------------------------------------------
//    // Stage 2: Hierarchical Mask Generation (Combinational -> FF)
//    // ----------------------------------------------------------------
    logic [3:0] block_limit;
    logic [4:0] local_limit;
    
//    // Driven entirely by the Stage 1 register
    assign block_limit = safe_limit_idx_reg[8:5];
    assign local_limit = safe_limit_idx_reg[4:0];

    logic [31:0] local_bid_mask;
    logic [31:0] local_ask_mask;
    assign local_bid_mask = (32'b1 << local_limit) - 32'd1;
    assign local_ask_mask = (local_limit == 5'd31) ? 32'd0 : ~((32'b1 << (local_limit + 5'd1)) - 32'd1);

    logic [511:0] active_mask_comb;

    always_comb begin
        for (int i = 0; i < 16; i++) begin
            if (IS_BID) begin
                if (cache_bottom_price == 24'd0 || safe_limit_idx_reg >= 511)
                    active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32];
                else if (safe_limit_idx_reg == 0)
                    active_mask_comb[i*32 +: 32] = 32'd0;
                else begin
                    if (i < block_limit)
                        active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32];
                    else if (i == block_limit)
                        active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32] & local_bid_mask;
                    else
                        active_mask_comb[i*32 +: 32] = 32'd0;
                end
            end else begin
//                // Ask logic
                if (cache_bottom_price == 24'hFFFFFF || safe_limit_idx_reg == 0)
                    active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32];
                else if (safe_limit_idx_reg >= 511)
                    active_mask_comb[i*32 +: 32] = 32'd0;
                else begin
                    if (i > block_limit)
                        active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32];
                    else if (i == block_limit)
                        active_mask_comb[i*32 +: 32] = price_mask[i*32 +: 32] & local_ask_mask;
                    else
                        active_mask_comb[i*32 +: 32] = 32'd0;
                end
            end
        end
    end

//    // Stage 2 Pipeline Register
    always_ff @(posedge clk) begin
        if (reset) active_mask_reg <= 512'd0;
        else       active_mask_reg <= active_mask_comb;
    end

//    // ----------------------------------------------------------------
//    // Stage 3: Priority Encoder 
//    // ----------------------------------------------------------------
    logic [8:0] best_index;
    logic       encoder_valid;

    hierarchical_encoder #(.IS_BID(IS_BID)) ENCODER (
        .mask_in(active_mask_reg), 
        .best_index(best_index),
        .valid(encoder_valid)
    );

//    // Port B: Continuous Read for Top-K Cache
    logic [8:0] addr_B;
    always_ff @(posedge clk) begin
        addr_B <= (best_index + base_ptr) & 511;
    end 

    always_ff @(posedge clk) begin
        bram_qty_out <= qty_bram[addr_B];
    end

//    // Reverse calculate price from index
    assign bram_price_out = encoder_valid ? (curr_center - 256 + best_index) : (IS_BID ? 24'd0 : 24'hFFFFFF);

//    // --- 3. Main Circular Buffer FSM ---
    logic signed [24:0] price_diff;
    logic signed [24:0] target_center_up;
    logic signed [24:0] target_center_down;
    
    assign price_diff         = $signed({1'b0, price}) - $signed({1'b0, curr_center});
    assign target_center_up   = $signed({1'b0, price}) - 255;
    assign target_center_down = $signed({1'b0, price}) + 256;

    always_ff @(posedge clk) begin
        if (reset) begin
            state       <= IDLE;
            busy        <= 0;
            price_mask  <= 0;
            curr_center <= 0;
            base_ptr    <= 0;
            we_A        <= 0;
        end else begin
            case(state)
                IDLE: begin
                    we_A <= 0;
                    if (insert_valid || cancel_valid) begin
                        busy <= 1;
                        is_insert_op <= insert_valid;
                        pending_qty  <= quantity;

//                        // First order initialization
                        if (curr_center == 0 && price_mask == 0) begin
                            curr_center <= price;
                            target_idx  <= 256;
                            state       <= MODIFY_READ;
                        end else if (price_diff > 255) begin
                           if (price_diff > 767) begin // Jump optimization: skip huge loops
                                curr_center <= target_center_up[23:0];
                                price_mask  <= 0;
                                target_idx  <= 511;
                                state       <= MODIFY_READ;
                            end else begin
                                state <= SHIFT_UP;
                            end
                        end else if (price_diff < -256) begin
                            if (price_diff < -768) begin // Jump optimization
                                curr_center <= target_center_down[23:0];
                                price_mask  <= 0;
                                target_idx  <= 0;
                                state       <= MODIFY_READ;
                            end else begin
                                state <= SHIFT_DOWN;
                            end
                        end else begin
                            target_idx <= price_diff[8:0] + 256;
                            state      <= MODIFY_READ;
                        end
                    end else begin
                        busy <= 0;
                    end
                end

                SHIFT_UP: begin
                    if ($signed({1'b0, curr_center}) < target_center_up) begin
                        curr_center <= curr_center + 1;
                        base_ptr    <= (base_ptr + 1) & 511;
                        price_mask  <= {1'b0, price_mask[511:1]};
                    end else begin
                        target_idx <= 511;
                        state      <= MODIFY_READ;
                    end
                end

                SHIFT_DOWN: begin
                    if ($signed({1'b0, curr_center}) > target_center_down) begin
                        curr_center <= curr_center - 1;
                        base_ptr    <= (base_ptr - 1) & 511;
                        price_mask  <= {price_mask[510:0], 1'b0};
                    end else begin
                        target_idx <= 0;
                        state      <= MODIFY_READ;
                    end
                end

                MODIFY_READ: begin
                    addr_A <= (target_idx + base_ptr) & 511;
                    we_A   <= 0;
                    state  <= MODIFY_WAIT; // 1 cycle wait for BRAM data
                end

                MODIFY_WAIT: begin
                    state <= MODIFY_WRITE;
                end

                MODIFY_WRITE: begin
                    we_A   <= 1;
                    addr_A <= addr_A; // Hold address
                    if (is_insert_op) begin
                        // If price_mask is 0, ignore BRAM garbage data!
                        din_A <= (price_mask[target_idx] ? dout_A : 0) + pending_qty;
                        price_mask[target_idx] <= 1'b1;
                  end else begin
                        if (price_mask[target_idx]) begin
                            if (dout_A <= pending_qty) begin
                                din_A <= 0;
                                price_mask[target_idx] <= 1'b0; // Lazy delete
                            end else begin
                                din_A <= dout_A - pending_qty;
                            end
                        end
                    end
                    state <= IDLE;
                    busy  <= 0; 
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule