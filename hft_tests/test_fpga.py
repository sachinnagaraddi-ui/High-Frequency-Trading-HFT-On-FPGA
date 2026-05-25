import serial
import struct
import time
import sys

sys.stdout.reconfigure(encoding='utf-8')

# 1. HARDWARE CONFIGURATION
SERIAL_PORT = "COM5"
BAUD_RATE = 115200

STOCKS = {0: "ABC", 1: "DEF", 2: "GHI", 3: "XYZ"}

# Protocol Constants
SOF = 0xAA
EOF = 0x55
MSG_ADD   = 0x4E  # 'N'
MSG_CXL   = 0x58  # 'X'
MSG_TRADE = 0x54  # 'T'
SIDE_BUY  = 0x42  # 'B'
SIDE_SELL = 0x53  # 'S'

BASE_PRICE = 10000
PRICE_BAND = 256
MIN_PRICE = BASE_PRICE - PRICE_BAND
MAX_PRICE = BASE_PRICE + PRICE_BAND


# 2. PACKET ENCODER

def pack_order(msg_type, token, side, price, qty, stock_id):
    header = struct.pack(">B B H B", SOF, msg_type, token, side)
    price_bytes = struct.pack(">I", price)[1:4]
    flags = (stock_id << 4) & 0xF0
    tail = struct.pack(">H B B", qty, flags, EOF)
    return header + price_bytes + tail


# 3. ROBUST UART PACKET READER

def read_packet(ser):
    while True:
        byte = ser.read(1)
        if not byte:
            return None
        if byte[0] == SOF:
            rest = ser.read(11)
            if len(rest) == 11 and rest[-1] == EOF:
                return byte + rest
            # else: discard and resync



# 4. PACKET DECODER (FIXED)

def parse_fpga_output(raw_bytes):
    """Decodes 12-byte quote packets from quote_serializer.sv"""

    # Packet must be exactly: [SOF ... EOF]
    if not raw_bytes or len(raw_bytes) != 12 or raw_bytes[0] != SOF or raw_bytes[-1] != EOF:
        return None

    # FPGA format:
    # [0]=SOF, [1]=msg_type, [2:4]=latency, [4]=side,
    # [5:8]=price(24b), [8:10]=qty, [10]=flags, [11]=EOF
    msg_type = raw_bytes[1]
    latency_cycles = struct.unpack(">H", raw_bytes[2:4])[0]
    side = raw_bytes[4]
    price = struct.unpack(">I", b"\x00" + raw_bytes[5:8])[0]
    qty = struct.unpack(">H", raw_bytes[8:10])[0]
    flags = raw_bytes[10]

    stock_id = (flags >> 4) & 0xF
    stock_name = STOCKS.get(stock_id, f"UNKNOWN({stock_id})")
    side_str = "BUY " if side == SIDE_BUY else ("SELL" if side == SIDE_SELL else "----")

    if msg_type == 0x4F:  # 'O'
        latency_ns = latency_cycles * 10  # 100MHz clock
        return (
            f"Stock: {stock_name} | {side_str} | "
            f"Price: ₹{price/100:.2f} | Quantity: {qty} | "
            f"HW LATENCY: {latency_cycles} cycles ({latency_ns} ns)"
        )

    return None


def bounded_price(seed):
    """Deterministically generate a price in [BASE_PRICE-256, BASE_PRICE+256]."""
    return BASE_PRICE + ((seed * 37) % (2 * PRICE_BAND + 1) - PRICE_BAND)


def build_test_cases(total_cases=50):
    """Build mixed ADD/CANCEL/TRADE test cases with ADD prices constrained to ±256."""
    cases = []
    last_buy_token = None
    last_sell_token = None
    next_token = 1

    for i in range(total_cases):
        slot = i % 6

        if slot in (0, 2, 4):
            side = SIDE_BUY if slot != 4 else SIDE_SELL
            qty = 50 + ((i * 25) % 125)
            price = bounded_price(i + 1)
            token = next_token
            next_token += 1

            if side == SIDE_BUY:
                last_buy_token = token
                side_str = "BUY"
            else:
                last_sell_token = token
                side_str = "SELL"

            packet = pack_order(MSG_ADD, token, side, price, qty, 0)
            desc = f"ADD {side_str} | Token {token} | Price: ₹{price/100:.2f} | Qty: {qty}"
            cases.append((packet, desc))
            continue

        if slot in (1, 5):
            if last_buy_token is not None:
                qty = 25 + ((i * 15) % 75)
                packet = pack_order(MSG_CXL, last_buy_token, SIDE_BUY, 0, qty, 0)
                desc = f"CANCEL | Token {last_buy_token} | Qty: {qty}"
                cases.append((packet, desc))
            else:
                price = bounded_price(i + 1)
                token = next_token
                next_token += 1
                last_buy_token = token
                packet = pack_order(MSG_ADD, token, SIDE_BUY, price, 100, 0)
                desc = f"ADD BUY | Token {token} | Price: ₹{price/100:.2f} | Qty: 100"
                cases.append((packet, desc))
            continue

        if last_sell_token is not None:
            qty = 20 + ((i * 10) % 60)
            packet = pack_order(MSG_TRADE, last_sell_token, SIDE_SELL, 0, qty, 0)
            desc = f"TRADE | Token {last_sell_token} | Qty: {qty}"
            cases.append((packet, desc))
        else:
            price = bounded_price(i + 1)
            token = next_token
            next_token += 1
            last_sell_token = token
            packet = pack_order(MSG_ADD, token, SIDE_SELL, price, 100, 0)
            desc = f"ADD SELL | Token {token} | Price: ₹{price/100:.2f} | Qty: 100"
            cases.append((packet, desc))

    return cases



# 5. SEND + LISTEN LOOP

def send_and_listen(ser, packet, description, listen_time=1):
    print(f"\n[TX] {description}")
    ser.write(packet)
    ser.flush()
    t_end = time.time() + listen_time

    while time.time() < t_end:
        resp = read_packet(ser)
        if resp:
            parsed = parse_fpga_output(resp)
            if parsed:
                print(f"  └── [FPGA QUOTE] {parsed}")

                # Correct quote-field extraction
                stock_id = (resp[10] >> 4) & 0xF
                side = resp[4]
                qty = struct.unpack(">H", resp[8:10])[0]

                trade_side = SIDE_SELL if side == SIDE_BUY else SIDE_BUY
                trade_packet = pack_order(MSG_TRADE, 999, trade_side, 0, qty, stock_id)

                print("  ┌── [EXCHANGE] Matched! Sending Trade Fill to FPGA...")
                ser.write(trade_packet)
                ser.flush()

        time.sleep(0.001)


# 6. TEST SCENARIO

def run_deterministic_test():
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=0.1)
        print(f"[INFO] Connected to {SERIAL_PORT} @ {BAUD_RATE}")
        print("[INFO] Starting 10-case mixed scenario for Stock ABC (price band: 10000 ± 256)...\n")

        test_cases = build_test_cases(total_cases=100)
        for packet, description in test_cases:
            send_and_listen(ser, packet, description)

        print("\n[INFO] Deterministic sequence complete.")
        
    except Exception as e:
        print(f"[ERROR] {e}")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()

if __name__ == "__main__":
    run_deterministic_test()