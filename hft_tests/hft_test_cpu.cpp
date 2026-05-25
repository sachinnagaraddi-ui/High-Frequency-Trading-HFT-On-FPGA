#include <iostream>
#include <vector>
#include <map>
#include <cstdint>
#include <iomanip>
#include <random>
#include <chrono>

// Protocol Constants from 'testcases' source [1]
const uint8_t SOF       = 0xAA;
const uint8_t EOF_BYTE  = 0x55;
const uint8_t MSG_ADD   = 0x4E;   // 'N'
const uint8_t MSG_CXL   = 0x58;   // 'X'
const uint8_t MSG_TRADE = 0x54;   // 'T'
const uint8_t SIDE_BUY  = 0x42;   // 'B'
const uint8_t SIDE_SELL = 0x53;   // 'S'

constexpr size_t MAX_STOCKS = 16;

// 12-byte Packet Structure matching Python 'pack_order' [2]
#pragma pack(push, 1)
struct HFTPacket {
    uint8_t  sof;        // Byte 0: 0xAA
    uint8_t  msg_type;   // Byte 1: ADD/CXL/TRADE
    uint16_t token;      // Bytes 2-3: Token (Big Endian)
    uint8_t  side;       // Byte 4: SIDE_BUY/SIDE_SELL
    uint8_t  price[3];   // Bytes 5-7: 24-bit Price
    uint16_t qty;        // Bytes 8-9: Quantity (Big Endian)
    uint8_t  flags;      // Byte 10: stock_id in upper 4 bits
    uint8_t  eof;        // Byte 11: 0x55
};
#pragma pack(pop)

class OrderBookSide {
private:
    bool is_bid;
    std::map<uint32_t, uint32_t> levels; 

public:
    OrderBookSide(bool bid) : is_bid(bid) {}

    void process_update(uint32_t price, uint32_t qty, bool add) {
        if (add) {
            levels[price] += qty;
        } else if (levels.count(price)) {
            // Replicates 'MODIFY_WRITE' subtraction logic [4]
            if (levels[price] <= qty) levels.erase(price);
            else levels[price] -= qty;
        }
    }

    std::pair<uint32_t, uint32_t> get_best() {
        if (levels.empty()) return {0, 0};
        if (is_bid) return {levels.rbegin()->first, levels.rbegin()->second};
        return {levels.begin()->first, levels.begin()->second};
    }
};

static uint16_t decode_be16(uint16_t value) {
    return static_cast<uint16_t>((value << 8) | (value >> 8));
}

class AdvancedMarketMaker {
public:
    int32_t position = 0;
    static constexpr int32_t MAX_POS = 500;
    static constexpr int32_t MIN_POS = -500;

    struct Quotes {
        uint32_t final_ask;
        uint32_t final_bid;
        uint16_t final_ask_qty;
        uint16_t final_bid_qty;
        bool final_ask_val;
        bool final_bid_val;
    };

    Quotes process_tick(bool best_bid_valid, bool best_ask_valid, 
                        uint32_t best_bid, uint32_t best_ask, 
                        uint32_t best_bid_qty, uint32_t best_ask_qty,
                        bool fill_valid, bool fill_side, uint32_t fill_qty) 
    {
        // 1A. Inventory Update
        int32_t nxt_position = position;
        if (fill_valid) {
            if (fill_side) nxt_position -= fill_qty; // 1 = Sell Fill
            else           nxt_position += fill_qty; // 0 = Buy Fill
        }
        position = nxt_position;

        Quotes q = {0, 0, 0, 0, false, false};

        // 1B. Stage 1 valid check
        if (best_bid_valid && best_ask_valid && best_ask > best_bid) {
            uint32_t spread = best_ask - best_bid;
            uint32_t stg1_mid = best_bid + (spread >> 1);
            uint32_t stg1_margin = (spread >> 2); // 25% of spread
            int32_t stg1_skew = nxt_position >> 6; // Must use bitwise >> to match SV's arithmetic >>> exactly

            bool stg1_bullish = best_bid_qty > (best_ask_qty << 2);
            bool stg1_bearish = best_ask_qty > (best_bid_qty << 2);

            bool stg1_block_buy = nxt_position >= MAX_POS;
            bool stg1_block_sell = nxt_position <= MIN_POS;

            // STAGE 2: ALU calculations
            int32_t calc_ask = (int32_t)stg1_mid + (int32_t)stg1_margin - stg1_skew;
            int32_t calc_bid = (int32_t)stg1_mid - (int32_t)stg1_margin - stg1_skew;

            if (stg1_bullish) {
                q.final_bid = stg1_mid;
                q.final_ask = 0xFFFFFF;
            } else if (stg1_bearish) {
                q.final_ask = stg1_mid;
                q.final_bid = 0;
            } else {
                q.final_ask = calc_ask > 0 ? (uint32_t)calc_ask : 0;
                q.final_bid = calc_bid > 0 ? (uint32_t)calc_bid : 0;
            }

            q.final_bid_val = !stg1_block_buy;
            q.final_ask_val = !stg1_block_sell;

            if (nxt_position > 200) {
                q.final_ask_qty = 200;
                q.final_bid_qty = 50;
            } else if (nxt_position < -200) {
                q.final_ask_qty = 50;
                q.final_bid_qty = 200;
            } else {
                q.final_ask_qty = 100;
                q.final_bid_qty = 100;
            }
        }
        return q;
    }
};

class HFTEngine {
public:
    std::vector<OrderBookSide> bids;
    std::vector<OrderBookSide> asks;
    std::vector<AdvancedMarketMaker> mms;
    std::map<uint16_t, uint32_t> token_to_price; // Maps Token ID to Price for Cancels/Trades

    HFTEngine()
        : bids(MAX_STOCKS, OrderBookSide(true)), asks(MAX_STOCKS, OrderBookSide(false)), mms(MAX_STOCKS) {}

    void handle_packet(const HFTPacket& pkt) {
        const auto start = std::chrono::high_resolution_clock::now();

        const uint8_t* raw = reinterpret_cast<const uint8_t*>(&pkt);
        std::cout << "[INPUT] Raw Bytes: ";
        for (int i = 0; i < 12; i++) {
            std::cout << std::hex << std::setw(2) << std::setfill('0') << (int)raw[i] << " ";
        }
        std::cout << std::dec << "\n";

        uint32_t price = (static_cast<uint32_t>(pkt.price[0]) << 16) |
                         (static_cast<uint32_t>(pkt.price[1]) << 8) |
                          static_cast<uint32_t>(pkt.price[2]);

        uint16_t token = decode_be16(pkt.token);
        uint16_t qty = decode_be16(pkt.qty);
        uint8_t stock_id = (pkt.flags >> 4) & 0x0F;
        if (stock_id >= MAX_STOCKS) {
            std::cout << "[ERROR] Invalid stock_id " << (int)stock_id << "\n";
            return;
        }

        bool fill_valid = (pkt.msg_type == MSG_TRADE);
        // The FPGA evaluates a SIDE_SELL byte (0x53) as a 0 (Buy Fill).
        // We flip the C++ check to pkt.side == SIDE_BUY to exactly mirror the hardware's parser behavior.
        bool fill_side = (pkt.side == SIDE_BUY); 
        uint32_t fill_qty = qty;

        if (pkt.msg_type == MSG_ADD) {
            token_to_price[token] = price; // Save price for future cancels/trades
            if (pkt.side == SIDE_BUY) bids[stock_id].process_update(price, qty, true);
            else asks[stock_id].process_update(price, qty, true);
        } else if (pkt.msg_type == MSG_CXL || pkt.msg_type == MSG_TRADE) {
            uint32_t actual_price = token_to_price.count(token) ? token_to_price[token] : price;
            // The FPGA interprets SIDE_BUY/SIDE_SELL exactly as the incoming packet's side bit
            if (pkt.side == SIDE_BUY) bids[stock_id].process_update(actual_price, qty, false);
            else asks[stock_id].process_update(actual_price, qty, false);
        }

        auto bb = bids[stock_id].get_best();
        auto ba = asks[stock_id].get_best();
        
        bool bb_valid = (bb.first > 0);
        bool ba_valid = (ba.first > 0);

        // Feed Market Data to Advanced Market Maker to generate Quotes!
        auto q = mms[stock_id].process_tick(bb_valid, ba_valid, 
                                            bb.first, ba.first, 
                                            bb.second, ba.second, 
                                            fill_valid, fill_side, fill_qty);

        const auto end = std::chrono::high_resolution_clock::now();
        const auto software_latency_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();

        // Convert the final generated quotes for display parity with FPGA quotes
        float out_bid = (q.final_bid_val && q.final_bid != 0xFFFFFF) ? (q.final_bid / 100.0f) : 0.0f;
        float out_ask = (q.final_ask_val && q.final_ask != 0xFFFFFF) ? (q.final_ask / 100.0f) : 0.0f;

        std::cout << "[OUTPUT] Stock: " << (int)stock_id
                  << " | Best Bid: " << std::fixed << std::setprecision(2) << out_bid
                  << " | Best Ask: " << out_ask
                  << " | SW Latency: " << software_latency_ns << "ns\n";
        std::cout << "------------------------------------------------------------\n";
    }
};

static HFTPacket make_packet(uint8_t msg_type,
                             uint16_t token,
                             uint8_t side,
                             uint32_t price,
                             uint16_t qty,
                             uint8_t stock_id) {
    HFTPacket pkt;
    pkt.sof = SOF;
    pkt.msg_type = msg_type;
    pkt.token = ((token >> 8) & 0xFF) | ((token & 0xFF) << 8);
    pkt.side = side;
    pkt.price[0] = static_cast<uint8_t>(price >> 16);
    pkt.price[1] = static_cast<uint8_t>(price >> 8);
    pkt.price[2] = static_cast<uint8_t>(price);
    pkt.qty = ((qty >> 8) & 0xFF) | ((qty & 0xFF) << 8);
    pkt.flags = static_cast<uint8_t>((stock_id & 0x0F) << 4);
    pkt.eof = EOF_BYTE;
    return pkt;
}

#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif

int main() {
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
#endif
    HFTEngine engine;
    HFTPacket pkt;

    // Read 12-byte packets continuously from stdin
    while (std::cin.read(reinterpret_cast<char*>(&pkt), sizeof(HFTPacket))) {
        engine.handle_packet(pkt);
    }
    
    return 0;
}