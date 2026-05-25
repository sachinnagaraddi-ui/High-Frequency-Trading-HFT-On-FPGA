# Design and Evaluation of a Latency-Deterministic FPGA-Based High-Frequency Trading (HFT) System

![Platform](https://img.shields.io/badge/Platform-Xilinx%20Zynq--7020-orange)
![Clock](https://img.shields.io/badge/Clock-100%20MHz-brightgreen)

# 📖 Overview

In modern high-frequency trading (HFT), temporal determinism and predictable tail latency are strict requirements that are challenging to guarantee in software-based environments due to operating system scheduling, context switching, and hardware interrupts.

This repository contains the RTL source code and evaluation framework for a fully deterministic, hardware-accelerated HFT pipeline implemented on a Field Programmable Gate Array (FPGA). By replacing variable-latency software arrays with a Hybrid Top-K Register Cache and a Circular Sparse Block RAM (BRAM) Architecture, this design eliminates the O(N) latency penalty of traditional memory shifting.

The empirical evaluations indicate that this microarchitecture evaluates market data and generates trading decisions with a highly deterministic latency of 7 clock cycles (70 nanoseconds at 100 MHz), effectively minimizing the unpredictable jitter characteristic of software-based systems.

✨ Key Architectural Features

Cycle-Deterministic RTL Pipeline:
Processes fixed-length (12-byte) market data and generates trading decisions in a strictly bounded timeframe.

Hybrid Order Book Engine:
- Top-K Cache: Parallel hardware registers provide O(1) access to the most competitive market prices.
- Circular Sparse BRAM: A 512-depth deep storage layer governed by a sliding window pointer, eliminating physical memory shifting during market price drifts.

Advanced Market Maker (AMM):
A 2-cycle DSP-based trading logic unit that calculates mid-price, market spread, and applies dynamic inventory skewing and risk-gating.

Backpressure-Aware Buffering:
A central 80-bit synchronous FIFO safely absorbs burst traffic without packet loss or timing violations.

🏗️ System Architecture

The trading pipeline is fully isolated within the Programmable Logic (PL) fabric of the Zynq-7020 SoC. The Host PC acts exclusively as a market data generator and metric visualization dashboard, communicating via a custom, hardware-accelerated Universal Asynchronous Receiver-Transmitter (UART) interface.

## 1. Ingress & Parsing

A custom UART core guarantees cycle-accurate ingestion. The fixed-length 12-byte binary protocol enables deterministic parsing using a highly optimized Finite State Machine (FSM).

- UART Interface
- Parser FSM

## 2. Hybrid Order Book (The Determinism Engine)

The core novelty of this microarchitecture is the hybrid memory structure. Standard BRAM structures require O(N) cycles to shift memory during price cancellations. Our design utilizes a dual-port architecture with a 3-stage pipelined DSP datapath and a 16×32 Hierarchical Priority Encoder. A control FSM modifies a `base_ptr` to achieve an O(1) logical sliding window over the 512-bit active price mask.

- Hybrid Order Book
- Circular Sparse BRAM Internal Architecture

## 3. Advanced Market Maker (AMM)

The trading logic executes in exactly 2 clock cycles using dedicated Digital Signal Processing (DSP) slices. It calculates dynamic quotes based on the best bid/ask prices while shifting inventory to calculate position skew (`Position >> 6`), and applies hard MAX_POS risk limits.

- Advanced Market Maker Logic

## 4. Pipeline Timing & Latency

System latency is empirically defined as the number of hardware clock cycles elapsed between the assertion of the `parse_valid` signal and the completion of the trading decision.

The pipeline guarantees a strict, data-independent latency of exactly 7 clock cycles:

```text
1 + 1 + 3 + 2 = 7 cycles
