`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.02.2026 15:29:16
// Design Name: 
// Module Name: packet_assembler
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


module packet_assembler(
    input clk,
    input reset,
    input [7:0] uart_byte,
    input rx_data_valid,      // From FIFO
    output reg [95:0] packet, // Full 12-byte packet
    output reg packet_valid   // Pulse high when packet is ready
);

    reg [3:0] byte_count;
    reg [95:0] shift_reg;
    reg active;

    always @(posedge clk) begin
        if (reset) begin
            byte_count <= 0;
            active <= 0;
            packet_valid <= 0;
            packet <= 0;
        end else begin
            packet_valid <= 0; // Default low
            
            if (rx_data_valid) begin
                // 1. Wait for Start of Frame (0xAA)
                if (!active) begin
                    if (uart_byte == 8'hAA) begin
                        active <= 1;
                        byte_count <= 1; // Byte 0 received
                        // Shift in MSB first (Big Endian)
                        shift_reg <= {shift_reg[87:0], uart_byte}; 
                    end
                end 
                // 2. Collect Body
                else begin
                    shift_reg <= {shift_reg[87:0], uart_byte}; // CRITICAL FIX: [87:0] not [89:0]
                    byte_count <= byte_count + 1;

                    // 3. Check End of Frame (Byte 11)
                    if (byte_count == 11) begin
                        if (uart_byte == 8'h55) begin
                            packet <= {shift_reg[87:0], uart_byte};
                            packet_valid <= 1; // Success!
                        end 
                        // Reset regardless of success/fail to hunt for next 0xAA
                        active <= 0;
                        byte_count <= 0;
                    end
                end
            end
        end
    end
endmodule