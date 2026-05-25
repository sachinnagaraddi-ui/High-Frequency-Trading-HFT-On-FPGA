`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 17.02.2026 19:43:21
// Design Name: 
// Module Name: hft_types
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

package hft_types;

    // 80-bit Parsed Order Structure
    typedef struct packed {
        logic [7:0]  msg_type;
        logic [15:0] token;       // order_id
        logic [7:0]  side;
        logic [23:0] price;
        logic [15:0] quantity;
        logic [3:0]  stock_id;
        logic [3:0]  flags;
    } order_t;
    
     typedef enum logic [1:0] {POP_FIFO, HASH_LOOKUP, FIRE_BOOK} ctrl_state_t;

    // Define States using Enum (Readable names instead of 0, 1, 2)
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        WRITE_MEM = 2'b01,
        WAIT_ACK = 2'b10
    } state_t;

endpackage