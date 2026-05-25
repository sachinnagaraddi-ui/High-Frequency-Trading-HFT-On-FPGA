# Design and Evaluation of a Latency-Deterministic FPGA-Based High-Frequency Trading (HFT) System

![Platform](https://img.shields.io/badge/Platform-Xilinx%20Zynq--7020-orange)
![Clock](https://img.shields.io/badge/Clock-100%20MHz-brightgreen)

# 📖 Overview

In modern high-frequency trading (HFT), temporal determinism and predictable tail latency are strict requirements that are challenging to guarantee in software-based environments due to operating system scheduling, context switching, and hardware interrupts.

This repository contains the RTL source code and evaluation framework for a fully deterministic, hardware-accelerated HFT pipeline implemented on a Field Programmable Gate Array (FPGA). By replacing variable-latency software arrays with a Hybrid Top-K Register Cache and a Circular Sparse Block RAM (BRAM) Architecture, this design eliminates the O(N) latency penalty of traditional memory shifting.

The empirical evaluations indicate that this microarchitecture evaluates market data and generates trading decisions with a highly deterministic latency of 7 clock cycles (70 nanoseconds at 100 MHz), effectively minimizing the unpredictable jitter characteristic of software-based systems.

# ✨ Key Architectural Features

1. Cycle-Deterministic RTL Pipeline:Processes fixed-length (12-byte) market data and generates trading decisions in a strictly bounded timeframe.

2. Hybrid Order Book Engine:
   - **Top-K Cache:** Parallel hardware registers provide `O(1)` access to the most competitive market prices.
   - **Circular Sparse BRAM:** A 512-depth deep storage layer governed by a sliding window pointer, eliminating physical memory shifting during market price drifts.

3. Advanced Market Maker (AMM):A 2-cycle DSP-based trading logic unit that calculates mid-price, market spread, and applies dynamic inventory skewing and risk-gating.

4. Backpressure-Aware Buffering:A central 80-bit synchronous FIFO safely absorbs burst traffic without packet loss or timing violations.

# 🏗️ System Architecture

The trading pipeline is fully isolated within the Programmable Logic (PL) fabric of the Zynq-7020 SoC. The Host PC acts exclusively as a market data generator and metric visualization dashboard, communicating via a custom, hardware-accelerated Universal Asynchronous Receiver-Transmitter (UART) interface.

<img width="654" height="261" alt="Screenshot 2026-05-25 at 5 54 13 PM" src="https://github.com/user-attachments/assets/04888477-3dfd-4d0c-959b-a37dc3e9ee84" />


## 1. Ingress & Parsing

A custom UART core guarantees cycle-accurate ingestion. The fixed-length 12-byte binary protocol enables deterministic parsing using a highly optimized Finite State Machine (FSM).

<img width="1008" height="560" alt="Screenshot 2026-05-25 at 5 57 11 PM" src="https://github.com/user-attachments/assets/869ae182-50a0-4357-8d29-d5b041e9bf50" />

<img width="1149" height="1369" alt="parser_final" src="https://github.com/user-attachments/assets/fa3eb2a9-6899-4aa3-8e5f-399e06e16b96" />

## 2. Hybrid Order Book (The Determinism Engine)

The core novelty of this microarchitecture is the hybrid memory structure. Standard BRAM structures require O(N) cycles to shift memory during price cancellations. Our design utilizes a dual-port architecture with a 3-stage pipelined DSP datapath and a 16×32 Hierarchical Priority Encoder. A control FSM modifies a `base_ptr` to achieve an O(1) logical sliding window over the 512-bit active price mask.

<img width="652" height="361" alt="Screenshot 2026-05-25 at 5 59 28 PM" src="https://github.com/user-attachments/assets/cc0f8d85-306b-41a5-8cb2-ff852d69a8d1" />
<img width="652" height="355" alt="Screenshot 2026-05-25 at 5 59 45 PM" src="https://github.com/user-attachments/assets/ab9350f4-af88-4fc7-966a-815de64a3c1a" />


## 3. Advanced Market Maker (AMM)

The trading logic executes in exactly 2 clock cycles using dedicated Digital Signal Processing (DSP) slices. It calculates dynamic quotes based on the best bid/ask prices while shifting inventory to calculate position skew (`Position >> 6`), and applies hard MAX_POS risk limits.



## 4. Pipeline Timing & Latency

System latency is empirically defined as the number of hardware clock cycles elapsed between the assertion of the `parse_valid` signal and the completion of the trading decision.

The pipeline guarantees a strict, data-independent latency of exactly 7 clock cycles:

```text
1 + 1 + 3 + 2 = 7 cycles
