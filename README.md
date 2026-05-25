# Design and Evaluation of a Latency-Deterministic FPGA-Based High-Frequency Trading (HFT) System

![Platform](https://img.shields.io/badge/Platform-Xilinx%20Zynq--7020-orange.svg)
![Frequency](https://img.shields.io/badge/Clock-100%20MHz-green.svg)

## 📖 Overview
In modern high-frequency trading (HFT), temporal determinism and predictable tail latency are strict requirements that are challenging to guarantee in software-based environments due to operating system scheduling, context switching, and hardware interrupts. 

This repository contains the RTL source code and evaluation framework for a fully deterministic, hardware-accelerated HFT pipeline implemented on a Field Programmable Gate Array (FPGA). By replacing variable-latency software arrays with a **Hybrid Top-K Register Cache** and a **Circular Sparse Block RAM (BRAM) Architecture**, this design eliminates the $O(N)$ latency penalty of traditional memory shifting.

The empirical evaluations indicate that this microarchitecture evaluates market data and generates trading decisions with a highly deterministic latency of **7 clock cycles (70 nanoseconds at 100 MHz)**, effectively minimizing the unpredictable jitter characteristic of software-based systems.

## ✨ Key Architectural Features
1. **Cycle-Deterministic RTL Pipeline:** Processes fixed-length (12-byte) market data and generates trading decisions in a strictly bounded timeframe.
2. **Hybrid Order Book Engine:** 
   - **Top-K Cache:** Parallel hardware registers provide $O(1)$ access to the most competitive market prices.
   - **Circular Sparse BRAM:** A 512-depth deep storage layer governed by a sliding window pointer, eliminating physical memory shifting during market price drifts.
3. **Advanced Market Maker (AMM):** A 2-cycle DSP-based trading logic unit that calculates mid-price, market spread, and applies dynamic inventory skewing and risk-gating.
4. **Backpressure-Aware Buffering:** A central 80-bit synchronous FIFO safely absorbs burst traffic without packet loss or timing violations.

---

## 🏗️ System Architecture

The trading pipeline is fully isolated within the Programmable Logic (PL) fabric of the Zynq-7020 SoC. The Host PC acts exclusively as a market data generator and metric visualization dashboard, communicating via a custom, hardware-accelerated Universal Asynchronous Receiver-Transmitter (UART) interface.

<img width="654" height="261" alt="Screenshot 2026-05-25 at 5 54 13 PM" src="https://github.com/user-attachments/assets/605cf9c3-6a0d-4d87-9c7b-9decc22f0af1" />


### 1. Ingress & Parsing
A custom UART core guarantees cycle-accurate ingestion. The fixed-length 12-byte binary protocol enables deterministic parsing using a highly optimized Finite State Machine (FSM).

<img width="1008" height="560" alt="Screenshot 2026-05-25 at 5 57 11 PM" src="https://github.com/user-attachments/assets/0ae0859d-7f33-4198-8155-32e8aa98f284" />
<img width="1149" height="1369" alt="parser_final" src="https://github.com/user-attachments/assets/59466afa-a815-4e3c-9564-227df84640e8" />


### 2. Hybrid Order Book (The Determinism Engine)
The core novelty of this microarchitecture is the hybrid memory structure. Standard BRAM structures require $O(N)$ cycles to shift memory during price cancellations. Our design utilizes a dual-port architecture with a 3-stage pipelined DSP datapath and a 16$\times$32 Hierarchical Priority Encoder. A control FSM modifies a `base_ptr` to achieve an $O(1)$ logical sliding window over the 512-bit active price mask.

<img width="652" height="361" alt="Screenshot 2026-05-25 at 5 59 28 PM" src="https://github.com/user-attachments/assets/4c7c1dd3-6eb2-40dc-b88d-6a350e0bcc34" />
<img width="652" height="355" alt="Screenshot 2026-05-25 at 5 59 45 PM" src="https://github.com/user-attachments/assets/807b0d1f-a46e-4093-9f25-9a60f1b35923" />


### 3. Advanced Market Maker (AMM)
The trading logic executes in exactly 2 clock cycles using dedicated Digital Signal Processing (DSP) slices. It calculates dynamic quotes based on the best bid/ask prices while shifting inventory to calculate position skew ($Position \gg 6$), and applies hard `MAX_POS` risk limits.
<img width="836" height="557" alt="Screenshot 2026-05-25 at 7 13 39 PM" src="https://github.com/user-attachments/assets/1cc15c6b-d492-41b1-b030-641eaf76ff38" />


### 4. Pipeline Timing & Latency
System latency is empirically defined as the number of hardware clock cycles elapsed between the assertion of the `parse_valid` signal and the completion of the trading decision. The pipeline guarantees a strict, data-independent latency of exactly **7 clock cycles** (1+1+3+2).

<img width="619" height="344" alt="Screenshot 2026-05-25 at 7 17 26 PM" src="https://github.com/user-attachments/assets/9ca109b9-a3ef-4f12-9789-03f69171d39d" />


---

## 📊 Software vs. Hardware Complexity

To provide a rigorous architectural baseline, a software equivalent of the trading engine was implemented in C++. The software utilizes standard `std::map` (Red-Black Trees) to maintain price-time priority. 

| Platform | Time Complexity | Jitter Profile | Execution Latency |
| :--- | :--- | :--- | :--- |
| **CPU (C++)** | $O(\log M + \log L)$ | High (OS Context Switching) | Unpredictable  |
| **FPGA (RTL)**| $O(1)$  | Zero Jitter | **Deterministic** |

While the software inherently requires logarithmic traversal latency for insertions and deletions, the hybrid FPGA hardware flattens these structures into memory arrays and registers, reducing the computational bounds to a strictly deterministic $O(1)$ latency per clock cycle.

---

## 📁 Codebase Overview (Vivado Hierarchy)

The directory structure directly mirrors the Xilinx Vivado hardware elaboration hierarchy.

```text
Design Sources
└── fpga_top (fpga_top.sv)
    ├── uart_if : uart_interface (uart_interface.v)
    │   ├── baud_gen : baud_rate_generator (baud_rate_generator.v)
    │   ├── rx_core : uart_receiver (uart_receiver.v)
    │   ├── rx_fifo : fifo (fifo.v)
    │   ├── tx_core : uart_transmitter (uart_transmitter.v)
    │   └── tx_fifo : fifo (fifo.v)
    └── core_inst : hft_core (hft_core.sv)
        ├── assembler : packet_assembler (packet_assembler.v)
        ├── parser : parsing (parsing.v)
        ├── id_map : order_id_map (order_id_map.sv)
        ├── burst_fifo : sync_fifo (sync_fifo.sv)
        ├── router : order_book_top (order_book.sv)
        │   ├── bid_book : order_book_half (order_book_half.sv)
        │   │   ├── cache : topk_cache (topk_cache.sv)
        │   │   └── deep_bram : circular_sparse_bram (circular_sparse_bram.sv)
        │   │       └── encoder : hierarchical_encoder (hierarchical_encoder.sv)
        │   └── ask_book : order_book_half (order_book_half.sv)
        │       ├── cache : topk_cache (topk_cache.sv)
        │       └── deep_bram : circular_sparse_bram (circular_sparse_bram.sv)
        │           └── encoder : hierarchical_encoder (hierarchical_encoder.sv)
        ├── amm : advanced_market_maker (trading_logic.sv)
        └── serializer : quote_serializer (quote_serializer.sv)

Global Packages
└── hft_types.sv

Constraints
└── zedboard_hft.xdc

Testing & Software Sources
├── hft_test_cpu.cpp
├── test_fpga.py
└── test_gui_hft.py
```

### Module Descriptions
*   **`fpga_top.sv`**: The absolute top-level wrapper. Hooks up physical ZedBoard pins (clock, reset button, UART RX/TX, LEDs) to internal logic.
*   **`uart_interface.v`**, **`baud_rate_generator.v`**, **`uart_receiver.v`**, **`uart_transmitter.v`**: The physical communication layer handling 115200 baud serial-to-parallel asynchronous conversion.
*   **`hft_core.sv`**: The central datapath routing the parser, FIFOs, order books, and AMM together.
*   **`packet_assembler.v`** & **`parsing.v`**: Extracts the fixed-length 12-byte (96-bit) blocks to isolate price, quantity, side, and token fields.
*   **`order_id_map.sv`**: A 1-cycle lookup table converting external 16-bit exchange tokens to internal 4-bit routing IDs.
*   **`sync_fifo.sv`**: The central burst buffer safeguarding against pipeline stalls during massive traffic spikes.
*   **`order_book.sv`** & **`order_book_half.sv`**: Limit order book representation. Wires the fast Top-K cache directly to the deeper BRAM spillover storage.
*   **`topk_cache.sv`**: Parallel hardware registers maintaining $O(1)$ constant-time access to the absolute best market prices.
*   **`circular_sparse_bram.sv`**: 512-depth Block RAM utilizing a sliding window FSM and pointer math to circumvent physical memory shifting.
*   **`hierarchical_encoder.sv`**: A highly optimized 3-stage priority encoder spanning a 512-bit active price mask to instantly locate refill prices for the cache.
*   **`trading_logic.sv`**: The Advanced Market Maker utilizing dedicated DSP slices for spread calculations and inventory-skewed quoting in 2 clock cycles.
*   **`quote_serializer.sv`**: Packages trade decisions back into 12-byte packets for Host PC transmission.
*   **`hft_types.sv`**: Global SystemVerilog package containing architecture-wide struct and state definitions.
*   **`hft_test_cpu.cpp`**: C++ software baseline (`std::map` Red-Black tree) serving as the latency benchmarking counterpart.
*   **`test_gui_hft.py`**: A Python Tkinter dashboard for real-time market simulation, latency tracking, and quote visualization.

---

## ⚙️ Hardware Setup & Usage
**Target Platform:** Digilent ZedBoard (Xilinx Zynq-7020 SoC)  
**Synthesis Tool:** Xilinx Vivado  

1. Import all files in `Design Sources` into a new Vivado RTL Project.
2. Add `zedboard_hft.xdc` to the Constraints folder.
3. Generate Bitstream and program the FPGA (Processing System is bypassed, runs purely on Programmable Logic).
4. Run the Host PC Python simulation:
   ```bash
   python test_gui_hft.py
   ```
5. Use the GUI to stream deterministic or burst market data patterns and observe the live 70ns hardware latency tracking versus CPU jitter.

## 👨‍💻 Developed By
**Vamshikrishna V Bidari** & **Sachin V Nagaraddi** 
*Department of Electronics and Communication Engineering*  
*National Institute of Technology Karnataka (NITK), Surathkal*
