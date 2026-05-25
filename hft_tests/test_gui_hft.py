import serial
import struct
import time
import threading
import random
import tkinter as tk
from tkinter import ttk
import subprocess
import os

import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg

# ==========================================
# CONFIG
# ==========================================
SERIAL_PORT = "COM5"
BAUD_RATE = 115200

SOF = 0xAA
EOF = 0x55

MSG_ADD   = 0x4E
MSG_CXL   = 0x58
MSG_TRADE = 0x54

SIDE_BUY  = 0x42
SIDE_SELL = 0x53

BASE_PRICE = 10000
STOCK_IDS = [0,1,2,3]
UART_PACKET_GAP = 0.00012

# ==========================================
# GLOBAL STORAGE
# ==========================================
fpga_latencies = []
cpu_latencies = []
live_quotes = []
running = False
STOCKS = {0: "AAPL", 1: "TSLA", 2: "GOOG", 3: "MSFT"}

# New storage for page 2 price tracking
fpga_quotes_bids = {0: [], 1: [], 2: [], 3: []}
fpga_quotes_asks = {0: [], 1: [], 2: [], 3: []}
cpu_quotes_bids = {0: [], 1: [], 2: [], 3: []}
cpu_quotes_asks = {0: [], 1: [], 2: [], 3: []}

current_page = 1

# ==========================================
# PACKET FORMAT & PARSER
# ==========================================
def pack_order(msg_type, token, side, price, qty, stock_id):
    header = struct.pack(">B B H B", SOF, msg_type, token, side)
    price_bytes = struct.pack(">I", price)[1:4]
    flags = (stock_id << 4) & 0xF0
    tail = struct.pack(">H B B", qty, flags, EOF)
    return header + price_bytes + tail

def read_packet(ser):
    while True:
        b = ser.read(1)
        if not b:
            return None
        if b[0] == SOF:
            rest = ser.read(11)
            if len(rest) == 11 and rest[-1] == EOF:
                return b + rest

def parse_fpga(raw):
    if not raw or len(raw) != 12:
        return None
    if raw[0] != SOF or raw[-1] != EOF:
        return None

    latency = struct.unpack(">H", raw[2:4])[0]
    return latency

def extract_quote_data(raw):
    if not raw or len(raw) != 12 or raw[0] != SOF or raw[-1] != EOF:
        return None
    if raw[1] != 0x4F: # Only quotes 'O'
        return None
    side = raw[4]
    price = struct.unpack(">I", b"\x00" + raw[5:8])[0]
    stock_id = (raw[10] >> 4) & 0xF
    return stock_id, side, price / 100.0

def format_quote(raw):
    if not raw or len(raw) != 12 or raw[0] != SOF or raw[-1] != EOF:
        return None
    msg_type = raw[1]
    if msg_type != 0x4F: # Only quotes 'O'
        return None
        
    latency_cycles = struct.unpack(">H", raw[2:4])[0]
    side = raw[4]
    price = struct.unpack(">I", b"\x00" + raw[5:8])[0]
    qty = struct.unpack(">H", raw[8:10])[0]
    stock_id = (raw[10] >> 4) & 0xF
    
    stock_name = STOCKS.get(stock_id, f"UNK({stock_id})")
    side_str = "BUY " if side == SIDE_BUY else ("SELL" if side == SIDE_SELL else "----")
    
    return f"{stock_name} | {side_str} | {price/100:.2f} | Q:{qty} | {latency_cycles}c"

# ==========================================
# CORE TEST CASES GENERATION
# ==========================================
SCENARIOS = [
    "Data Pattern 1",
    "Data Pattern 2",
    "Data Pattern 3",
    "Data Pattern 4",
    "Data Pattern 5"
]

def build_scenario_traffic(scenario="Data Pattern 1", n_total=200, stock_ids=STOCK_IDS):
    cases = []
    n_per_stock = n_total // len(stock_ids)
    token = 1
    per_stock = {
        s: {"remaining": n_per_stock, "last_buy": None, "last_sell": None} 
        for s in stock_ids
    }
    active_stocks = [s for s in stock_ids if n_per_stock > 0]

    while active_stocks:
        stock_id = random.choice(active_stocks)
        state = per_stock[stock_id]
        sent_for_stock = n_per_stock - state["remaining"]

        # 1. Always safely initialize book with a bid and ask within window
        if sent_for_stock == 0:
            cases.append(pack_order(MSG_ADD, token, SIDE_BUY, BASE_PRICE - 10, 100, stock_id))
            state["last_buy"] = token
            token += 1
        elif sent_for_stock == 1:
            cases.append(pack_order(MSG_ADD, token, SIDE_SELL, BASE_PRICE + 10, 100, stock_id))
            state["last_sell"] = token
            token += 1
        else:
            # 2. All 5 options use the "Mixed Traffic" structure but vary the injected data
            i = sent_for_stock - 2
            slot = i % 6
            
            if scenario == "Data Pattern 1":
                qty = 50 + (i % 100)
                price = BASE_PRICE + ((i * 37) % 60 - 30)
            elif scenario == "Data Pattern 2":
                qty = 10 + (i % 50)
                price = BASE_PRICE + ((i * 17) % 50 - 25)
            elif scenario == "Data Pattern 3":
                qty = 100 + (i % 200)
                price = BASE_PRICE + ((i * 23) % 40 - 20)
            elif scenario == "Data Pattern 4":
                qty = 25 + (i % 25)
                price = BASE_PRICE + ((i * 53) % 70 - 35)
            else: # "Data Pattern 5"
                qty = 200 + (i % 50)
                price = BASE_PRICE + ((i * 71) % 90 - 45)
                
            if slot in [0, 2, 4]:
                side = SIDE_BUY if slot != 4 else SIDE_SELL
                cases.append(pack_order(MSG_ADD, token, side, price, qty, stock_id))
                if side == SIDE_BUY: state["last_buy"] = token
                else: state["last_sell"] = token
                token += 1
            elif slot in [1, 5] and state["last_buy"]:
                cases.append(pack_order(MSG_CXL, state["last_buy"], SIDE_BUY, 0, qty, stock_id))
            elif state["last_sell"]:
                cases.append(pack_order(MSG_TRADE, state["last_sell"], SIDE_SELL, 0, qty, stock_id))

        state["remaining"] -= 1
        if state["remaining"] <= 0:
            active_stocks.remove(stock_id)

    return cases

# ==========================================
# TEST RUNNERS (CPU & FPGA)
# ==========================================
def run_test():
    global running, fpga_latencies, cpu_latencies
    running = True

    # Clear previous metrics in GUI
    root.after(0, lambda: fpga_latencies.clear())
    root.after(0, lambda: cpu_latencies.clear())
    root.after(0, lambda: live_quotes.clear())
    for i in range(4):
        fpga_quotes_bids[i].clear()
        fpga_quotes_asks[i].clear()
        cpu_quotes_bids[i].clear()
        cpu_quotes_asks[i].clear()
    metrics_text.set("Running test sequence...")
    
    scenario_name = scenario_var.get()
    packets = build_scenario_traffic(scenario=scenario_name, n_total=200) # 200 total packets
    
    # 1. CPU Testing
    exe_path = "hft_test_cpu.exe"
    if os.path.exists(exe_path):
        import subprocess
        # Write binary stream to a temporary file
        with open("cpu_input.bin", "wb") as f:
            for p in packets:
                f.write(p)
        
        try:
            # Capture output
            with open("cpu_input.bin", "rb") as f:
                # Provide explicitly closed bytes array stream so Windows ends nicely
                res = subprocess.run([exe_path], stdin=f, capture_output=True, text=True)
            
            cpu_last_bb = {0: -1, 1: -1, 2: -1, 3: -1}
            cpu_last_ba = {0: -1, 1: -1, 2: -1, 3: -1}
            cpu_packet_idx = 0
            
            for line in res.stdout.splitlines():
                if "[OUTPUT] Stock:" in line:
                    # Example format: [OUTPUT] Stock: 0 | Best Bid: 99.90 | Best Ask: 100.10 | SW Latency: 1234ns
                    parts = [p.strip() for p in line.split("|")]
                    stock_id = int(parts[0].split(":")[1].strip())
                    bb = float(parts[1].split(":")[1].strip())
                    ba = float(parts[2].split(":")[1].strip())
                    lat_str = parts[3].split(":")[1].split("ns")[0].strip()
                    
                    lat = int(lat_str)
                    cpu_latencies.append(lat // 10)
                    
                    if bb > 0 and cpu_last_bb[stock_id] != bb:
                        cpu_quotes_bids[stock_id].append((cpu_packet_idx, bb))
                        cpu_last_bb[stock_id] = bb
                    if ba > 0 and cpu_last_ba[stock_id] != ba:
                        cpu_quotes_asks[stock_id].append((cpu_packet_idx, ba))
                        cpu_last_ba[stock_id] = ba
                        
                    cpu_packet_idx += 1
                        
        except Exception as e:
            print("Failed to run CPU exe:", e)
    else:
        print("[WARN] hft_test_cpu.exe not found! Please build hft_test_cpu.cpp first.")

    # 2. FPGA Testing
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=0.05)
        
        if True: # Always use Reference mode loop since Burst is disabled
            for i, pkt in enumerate(packets):
                if not running: break
                ser.write(pkt)
                ser.flush()
                # Fixed gap, wait and receive
                t_end = time.time() + 0.25
                while time.time() < t_end:
                    resp = read_packet(ser)
                    if resp:
                        lat = parse_fpga(resp)
                        if lat is not None:
                            fpga_latencies.append(lat)
                            
                        q_data = extract_quote_data(resp)
                        if q_data:
                            sid, side, price = q_data
                            if side == SIDE_BUY:
                                fpga_quotes_bids[sid].append((i, price))
                            elif side == SIDE_SELL:
                                fpga_quotes_asks[sid].append((i, price))

                        q_str = format_quote(resp)
                        if q_str:
                            live_quotes.append(q_str)
                            if len(live_quotes) > 30:
                                live_quotes.pop(0)
                        break

        # elif mode == 'Burst':
        #     chunk_size = 50
        #     for i in range(0, len(packets), chunk_size):
        #         if not running: break
        #         chunk = packets[i:i+chunk_size]
        #         
        #         # Send 50 at once
        #         for pkt in chunk:
        #             ser.write(pkt)
        #             # Small hardware gap to ensure clean UART if needed
        #             time.sleep(UART_PACKET_GAP)
        #         ser.flush()
        #         
        #         # Stop and wait to receive all our FPGA's outputs
        #         t_end = time.time() + 1.0 # 1 second max wait per chunk
        #         received_in_chunk = 0
        #         
        #         while time.time() < t_end and received_in_chunk < len(chunk):
        #             resp = read_packet(ser)
        #             if resp:
        #                 lat = parse_fpga(resp)
        #                 if lat is not None:
        #                     fpga_latencies.append(lat)
        #                 received_in_chunk += 1

        ser.close()
    except Exception as e:
        root.after(0, lambda: status_label.config(text=f"FPGA Error: {e}"))

    running = False
    root.after(0, final_update_plot)
    root.after(0, lambda: status_label.config(text="Test Complete"))

# ==========================================
# GUI PLOT UPDATER
# ==========================================
def update_plot():
    if not running:
        return
        
    draw_plot()
    root.after(500, update_plot)

def final_update_plot():
    draw_plot()

def draw_plot():
    fig.clear()
    
    if current_page == 1:
        ax_time_fpga = fig.add_subplot(2, 2, 1)
        ax_time_cpu = fig.add_subplot(2, 2, 2)
        ax_hist_fpga = fig.add_subplot(2, 2, 3)
        ax_hist_cpu = fig.add_subplot(2, 2, 4)

        for ax in [ax_time_fpga, ax_time_cpu, ax_hist_fpga, ax_hist_cpu]:
            ax.set_facecolor('#1e1e1e')
            ax.tick_params(colors='white')
            ax.xaxis.label.set_color('white')
            ax.yaxis.label.set_color('white')
            ax.title.set_color('white')
            for spine in ax.spines.values():
                spine.set_color('#444444')
        
        # 1A. FPGA OVER TIME
        if fpga_latencies:
            ax_time_fpga.plot(fpga_latencies, 'o-', alpha=0.9, color='#00ff00', label="FPGA")
            ax_time_fpga.set_ylim([0, max(20, max(fpga_latencies) * 1.5)])
        
        # 1B. CPU OVER TIME
        if cpu_latencies:
            ax_time_cpu.plot(cpu_latencies, '-', alpha=0.6, color='#ff0000', label="CPU")
            ax_time_cpu.set_ylim([0, max(1000, max(cpu_latencies) * 1.2)])

        ax_time_fpga.set_title("1. FPGA Latency Tracking", fontsize=11)
        ax_time_fpga.set_ylabel("Latency (Cycles)")
        if fpga_latencies:
            ax_time_fpga.legend(loc="upper right")

        ax_time_cpu.set_title("2. CPU Latency Tracking", fontsize=11)
        if cpu_latencies:
            ax_time_cpu.legend(loc="upper right")

        # 2. FPGA DISTRIBUTION (Bottom Left)
        if fpga_latencies:
            ax_hist_fpga.hist(fpga_latencies, bins=15, color='#00ff00', alpha=0.8, edgecolor='black')
        ax_hist_fpga.set_title("3. FPGA Determinism", fontsize=11)
        ax_hist_fpga.set_xlabel("Latency (Cycles)")
        ax_hist_fpga.set_ylabel("Frequency Count")

        # 3. CPU DISTRIBUTION (Bottom Right)
        if cpu_latencies:
            ax_hist_cpu.hist(cpu_latencies, bins=50, range=(0, 500), color='#ff0000', alpha=0.8, edgecolor='black')
            ax_hist_cpu.set_xlim([0, 500])
        ax_hist_cpu.set_title("4. CPU Jitter Distribution", fontsize=11)
        ax_hist_cpu.set_xlabel("Latency (Cycles)")
        ax_hist_cpu.set_ylabel("Frequency Count")

    else:
        # Page 2: Stock Prices CPU vs FPGA (Only quotes)
        for i, stock_id in enumerate([0, 1, 2, 3]):
            ax = fig.add_subplot(2, 2, i + 1)
            ax.set_facecolor('#1e1e1e')
            ax.tick_params(colors='white')
            ax.xaxis.label.set_color('white')
            ax.yaxis.label.set_color('white')
            ax.title.set_color('white')
            for spine in ax.spines.values():
                spine.set_color('#444444')
                
            stock_name = STOCKS.get(stock_id, f"Stock {stock_id}")
            ax.set_title(f"Quote Tracking: {stock_name}", fontsize=11)
            ax.set_xlabel("Packet Sequence")
            ax.set_ylabel("Price")
            
            # Plot CPU Bids/Asks (Drawn in lines or step plots)
            if cpu_quotes_bids[stock_id]:
                bx, by = zip(*cpu_quotes_bids[stock_id])
                ax.plot(bx, by, '-', color='#ff5555', alpha=0.6, label="CPU Bid")
            if cpu_quotes_asks[stock_id]:
                ax_x, ay = zip(*cpu_quotes_asks[stock_id])
                ax.plot(ax_x, ay, '-', color='#ffaaaa', alpha=0.6, label="CPU Ask")
                
            # Plot FPGA Bids/Asks
            if fpga_quotes_bids[stock_id]:
                bx, by = zip(*fpga_quotes_bids[stock_id])
                ax.plot(bx, by, '-', color='#00ff00', linewidth=2, alpha=0.9, label="FPGA Bid")
            if fpga_quotes_asks[stock_id]:
                ax_x, ay = zip(*fpga_quotes_asks[stock_id])
                ax.plot(ax_x, ay, '-', color='#aaffaa', linewidth=2, alpha=0.9, label="FPGA Ask")
                
            if cpu_quotes_bids[stock_id] or fpga_quotes_bids[stock_id]:
                ax.legend(loc="best", fontsize=8)

    fig.tight_layout(pad=3.0)
    canvas.draw()
    
    # Calculate Live Metrics
    cpu_avg = sum(cpu_latencies)/len(cpu_latencies) if cpu_latencies else 0
    fpga_avg = sum(fpga_latencies)/len(fpga_latencies) if fpga_latencies else 0
    cpu_max = max(cpu_latencies) if cpu_latencies else 0
    fpga_max = max(fpga_latencies) if fpga_latencies else 0
    
    metrics_text.set(
        f"--- DASHBOARD METRICS ---\n\n"
        f"Orders Processed:\n"
        f"  Total sent   : {len(cpu_latencies)} (CPU)\n"
        f"  FPGA         : {len(fpga_latencies)}\n\n"
        f"Average Latency:\n"
        f"  CPU Model    : {cpu_avg:.2f} cycles\n"
        f"  FPGA Model   : {fpga_avg:.2f} cycles\n\n"
        f"Max Jitter / Peak Latency:\n"
        f"  CPU Peak     : {cpu_max:d} cycles\n"
        f"  FPGA Peak    : {fpga_max:d} cycles\n"
    )
    
    # Update Quotes Log
    quotes_list.config(state=tk.NORMAL)
    quotes_list.delete('1.0', tk.END)
    quotes_list.insert(tk.END, "\n".join(live_quotes))
    quotes_list.config(state=tk.DISABLED)
    quotes_list.yview(tk.END)

def toggle_page():
    global current_page
    current_page = 2 if current_page == 1 else 1
    page_btn.config(text=f"Page {current_page}/2 ➔")
    draw_plot()

def start_test_thread():
    global running
    if running: return
    status_label.config(text="Running...", foreground="#00aa00")
    threading.Thread(target=run_test, daemon=True).start()
    update_plot()

# ==========================================
# MAIN GUI LAYOUT
# ==========================================
root = tk.Tk()
root.title("HFT on FPGA - Ultra-Low Latency Dashboard")
try:
    root.state('zoomed') # Windows full screen mode
except:
    root.attributes('-zoomed', True) # Linux fallback

# Dark mode styling
style = ttk.Style()
style.theme_use('clam')
root.configure(bg="#2b2b2b")

# --- Top Control Bar ---
top_frame = tk.Frame(root, bg="#2b2b2b", pady=15, padx=20)
top_frame.pack(side=tk.TOP, fill=tk.X)

title_lbl = tk.Label(top_frame, text="HFT ARCHITECTURE BENCHMARK", font=("Proxima Nova", 24, "bold"), bg="#2b2b2b", fg="#ffffff")
title_lbl.pack(side=tk.LEFT)

scenario_var = tk.StringVar(value="Data Pattern 1")
tk.Label(top_frame, text="Test Scenario:", font=("Arial", 14), bg="#2b2b2b", fg="#ccc").pack(side=tk.LEFT, padx=(50, 5))
scenario_menu = ttk.OptionMenu(top_frame, scenario_var, "Data Pattern 1", *SCENARIOS)
scenario_menu.pack(side=tk.LEFT)

btn = tk.Button(top_frame, text="▶ START TEST", command=start_test_thread, font=("Arial", 14, "bold"), bg="#007acc", fg="white", activebackground="#009acc", borderwidth=0, padx=15, pady=5)
btn.pack(side=tk.LEFT, padx=30)

page_btn = tk.Button(top_frame, text="Page 1/2 ➔", command=toggle_page, font=("Arial", 14, "bold"), bg="#444444", fg="white", activebackground="#666666", borderwidth=0, padx=15, pady=5)
page_btn.pack(side=tk.LEFT, padx=15)

status_label = tk.Label(top_frame, text="Ready", font=("Arial", 14, "italic"), bg="#2b2b2b", fg="#aaaaaa")
status_label.pack(side=tk.RIGHT)

# --- Grid / Main Dashboard Elements ---
main_pane = tk.PanedWindow(root, orient=tk.HORIZONTAL, bg="#2b2b2b")
main_pane.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

# Left Side : Graphs
graph_frame = tk.Frame(main_pane, bg="#1e1e1e")
main_pane.add(graph_frame, stretch="always", minsize=800)

# Make the UI resolution very high definition (HD)
fig = plt.Figure(figsize=(14, 9), dpi=120, facecolor="#1e1e1e")

canvas = FigureCanvasTkAgg(fig, master=graph_frame)
canvas.get_tk_widget().pack(side=tk.TOP, fill=tk.BOTH, expand=True)

# Right Side : Metrics
metric_frame = tk.Frame(main_pane, bg="#151515", bd=2, relief=tk.RIDGE)
main_pane.add(metric_frame, stretch="never", minsize=450)

tk.Label(metric_frame, text="LIVE METRICS", font=("Consolas", 18, "bold"), bg="#151515", fg="#00ff00").pack(pady=(20, 10))

metrics_text = tk.StringVar()
metrics_text.set("Select mode and start\nto gauge performance.")
val_lbl = tk.Label(metric_frame, textvariable=metrics_text, font=("Consolas", 16), bg="#151515", fg="#00e5ff", justify=tk.LEFT, anchor="w")
val_lbl.pack(padx=20, fill=tk.X)

separator = ttk.Separator(metric_frame, orient='horizontal')
separator.pack(fill='x', pady=20, padx=10)

# Right Side : Live Quotes Log
tk.Label(metric_frame, text="LIVE QUOTES FEED", font=("Consolas", 18, "bold"), bg="#151515", fg="#ffaa00").pack(pady=(10, 5))

quotes_frame = tk.Frame(metric_frame, bg="#0d0d0d")
quotes_frame.pack(padx=10, pady=5, fill=tk.BOTH, expand=True)

quotes_list = tk.Text(quotes_frame, height=20, width=55, bg="#0d0d0d", fg="#00ff00", font=("Consolas", 11), state=tk.DISABLED, bd=0)
quotes_list.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(10, 0), pady=10)

# Scrollbar for Quotes
scrollbar = tk.Scrollbar(quotes_frame, command=quotes_list.yview, bg="#151515")
scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
quotes_list.config(yscrollcommand=scrollbar.set)

info_txt = (
    "Reference Mode: UART sends one packet,\n"
    "waits for FPGA response, records latency.\n\n"
    "# Burst Mode (Disabled).\n\n"
    "CPU Test is integrated via C++ stream.\n"
)
tk.Label(metric_frame, text=info_txt, font=("Arial", 11), bg="#151515", fg="#888", justify=tk.LEFT).pack(side=tk.BOTTOM, pady=20, padx=20)

# Initial empty draw
draw_plot()

if __name__ == '__main__':
    root.mainloop()