//`timescale 1ns / 1ps

//module hierarchical_encoder #(
//    parameter IS_BID = 1 // 1 for Bids (Finds MSB), 0 for Asks (Finds LSB)
//)(
//    input  logic          clk,
//    input  logic [1023:0] mask_in,     // The active price levels (masked for Top-K limit by parent)
//    output logic [9:0]    best_index,  // The 10-bit index of the next best price
//    output logic          valid        // High if at least one bit was set
//);

//    // -------------------------------------------------------------------------
//    // Stage 1: 32 parallel encoders operating on 32-bit chunks
//    // -------------------------------------------------------------------------
//    logic [31:0] block_valid_stg1;
//    logic [4:0]  local_indices_stg1 [0:31];

//    always_ff @(posedge clk) begin
//        for (int i = 0; i < 32; i++) begin
//            block_valid_stg1[i]   <= 1'b0;
//            local_indices_stg1[i] <= 5'd0;

//            if (IS_BID) begin
//                // BID: Find Highest Set Bit (MSB) in this 32-bit block
//                for (int j = 31; j >= 0; j--) begin
//                    if (mask_in[i*32 + j]) begin
//                        block_valid_stg1[i]   <= 1'b1;
//                        local_indices_stg1[i] <= j[4:0];
//                        break; 
//                    end
//                end
//            end else begin
//                // ASK: Find Lowest Set Bit (LSB) in this 32-bit block
//                for (int j = 0; j <= 31; j++) begin
//                    if (mask_in[i*32 + j]) begin
//                        block_valid_stg1[i]   <= 1'b1;
//                        local_indices_stg1[i] <= j[4:0];
//                        break; 
//                    end
//                end
//            end
//        end
//    end

//    // -------------------------------------------------------------------------
//    // Stage 2: Final 32-bit encoder to find the best overall block
//    // -------------------------------------------------------------------------
//    always_ff @(posedge clk) begin
//        valid      <= 1'b0;
//        best_index <= 10'd0;

//        if (IS_BID) begin
//            // BID: Scan blocks starting from the top (Block 31 down to 0)
//            for (int i = 31; i >= 0; i--) begin
//                if (block_valid_stg1[i]) begin
//                    valid      <= 1'b1;
//                    // Final index = (block_index * 32) + local_index
//                    best_index <= {i[4:0], local_indices_stg1[i]};
//                    break;
//                end
//            end
//        end else begin
//            // ASK: Scan blocks starting from the bottom (Block 0 up to 31)
//            for (int i = 0; i <= 31; i++) begin
//                if (block_valid_stg1[i]) begin
//                    valid      <= 1'b1;
//                    best_index <= {i[4:0], local_indices_stg1[i]};
//                    break;
//                end
//            end
//        end
//    end

//endmodule

`timescale 1ns / 1ps

module hierarchical_encoder #(
    parameter IS_BID = 1
)(
    input  logic [511:0] mask_in,     // REDUCED: 512 bits
    output logic [8:0]   best_index,  // REDUCED: 9-bit index (0 to 511)
    output logic         valid
);
    // Break 512 bits into 16 blocks of 32 bits
    logic [15:0] block_valid;         
    logic [3:0]  best_block;          
    logic [4:0]  best_local [0:15];   

    // 1. Determine which 32-bit blocks have at least one valid bit
    always_comb begin
        for (int i = 0; i < 16; i++) begin
            block_valid[i] = |mask_in[i*32 +: 32];
        end
    end

    // 2. Find the best block (16-to-4 Priority Encoder)
    always_comb begin
        best_block = 4'd0; 
        if (IS_BID) begin
            // Bids: Find the HIGHEST valid block (MSB to LSB)
            for (int i = 15; i >= 0; i--) begin
                if (block_valid[i]) begin
                    best_block = i[3:0];
                    break;
                end
            end
        end else begin
            // Asks: Find the LOWEST valid block (LSB to MSB)
            for (int i = 0; i < 16; i++) begin
                if (block_valid[i]) begin
                    best_block = i[3:0];
                    break;
                end
            end
        end
    end

    // 3. Find the best local index within each block (32-to-5 Priority Encoders)
    always_comb begin
        for (int i = 0; i < 16; i++) begin
            best_local[i] = 5'd0;
            if (IS_BID) begin
                // Bids: Find the HIGHEST valid bit in the 32-bit block
                for (int j = 31; j >= 0; j--) begin
                    if (mask_in[i*32 + j]) begin
                        best_local[i] = j[4:0];
                        break;
                    end
                end
            end else begin
                // Asks: Find the LOWEST valid bit in the 32-bit block
                for (int j = 0; j < 32; j++) begin
                    if (mask_in[i*32 + j]) begin
                        best_local[i] = j[4:0];
                        break;
                    end
                end
            end
        end
    end
    
    // 4. Final Output Assignment
    assign best_index = {best_block, best_local[best_block]};
    assign valid = |block_valid;

endmodule