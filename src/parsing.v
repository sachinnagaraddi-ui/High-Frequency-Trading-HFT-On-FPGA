`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.02.2026 15:29:16
// Design Name: 
// Module Name: parsing
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

module parsing(
    input clk,
    input reset,                 
    input [95:0] packet_in,
    input packet_valid_in,
    
    // Extracted Fields
    output reg [7:0] msg_type,
    output reg [15:0] token,
    output reg [7:0] side,
    output reg [23:0] price,
    output reg [15:0] quantity,
    output reg [3:0] stock_id,
    output reg [3:0] flags,      // ADDED: To parse the entire packet
    output reg parse_valid
);

    always @(posedge clk) begin
        if (reset) begin          
            msg_type <= 0;
            token <= 0;
            side <= 0;
            price <= 0;
            quantity <= 0;
            stock_id <= 0;
            flags <= 0;
            parse_valid <= 0;
        end 
        else if (packet_valid_in) begin
            // SECURITY CHECK: Only parse if SOF (0xAA) and EOF (0x55) are in the correct positions
            if (packet_in[95:88] == 8'hAA && packet_in[7:0] == 8'h55) begin
                msg_type <= packet_in[87:80];   // Byte 1
                token    <= packet_in[79:64];   // Bytes 2-3
                side     <= packet_in[63:56];   // Byte 4
                price    <= packet_in[55:32];   // Bytes 5-7
                quantity <= packet_in[31:16];   // Bytes 8-9
                stock_id <= packet_in[15:12];   // Byte 10 (upper half)
                flags    <= packet_in[11:8];    // Byte 10 (next half)
                parse_valid <= 1;               // Valid Packet!
            end else begin
                parse_valid <= 0;               // Corrupt packet, ignore it
            end
        end else begin
            parse_valid <= 0;
        end
    end
endmodule