# ----------------------------------------------------------------------------
# 1. System Clock (100 MHz)
# Source: Pin Y9 is the 100MHz Oscillator (Bank 13, 3.3V)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN Y9 [get_ports {clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk}]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports {clk}]

# ----------------------------------------------------------------------------
# 2. Reset Button (BTNC - Center Push Button)
# Source: Pin P16 (Bank 34). Default Vadj is 2.5V on ZedBoard.
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN P16 [get_ports {reset}]
set_property IOSTANDARD LVCMOS25 [get_ports {reset}]

# ----------------------------------------------------------------------------
# 3. User LEDs (LD0 - LD7)
# Each bit must be assigned individually
# ----------------------------------------------------------------------------
# LD0
set_property PACKAGE_PIN T22 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

# LD1
set_property PACKAGE_PIN T21 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

# LD2
set_property PACKAGE_PIN U22 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

# LD3
set_property PACKAGE_PIN U21 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

# LD4
set_property PACKAGE_PIN V22 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]

# LD5
set_property PACKAGE_PIN W22 [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]

# LD6
set_property PACKAGE_PIN U19 [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]

# LD7
set_property PACKAGE_PIN U14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]

# ----------------------------------------------------------------------------
# 4. Pmod Header JA (Top Row) for USB-UART
# ----------------------------------------------------------------------------
# JA2 (AA11) → FPGA TX
set_property PACKAGE_PIN AA11 [get_ports {tx}]
set_property IOSTANDARD LVCMOS33 [get_ports {tx}]

# JA3 (Y10) → FPGA RX
set_property PACKAGE_PIN Y10 [get_ports {rx}]
set_property IOSTANDARD LVCMOS33 [get_ports {rx}]