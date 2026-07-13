# Copyright 2026 M. I. E. ARDJOUNE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
# =============================================================================
# File   : physical.xdc
# Project: qmtech-workspace / ecc_hardware_accelerator_G (ecc_uart_top)
# Board  : QMTECH Artix-7 (xc7a100tfgg676-1)
# =============================================================================

# ---------------------------------------------------------------------------
# Clock
# ---------------------------------------------------------------------------
# clk_in1_0 is used directly as the system clock -- this design has no MMCM/PLL
# Default assumption below is a 50 MHz board oscillator, matching U22 of the board. If your
# carrier board's oscillator on this pin runs at a different frequency,
# update the period here *and* CLK_FREQ_HZ in params.txt to match
# they must agree, since CLK_FREQ_HZ is what the UART baud-rate divider
# in uart_tx.sv/uart_rx.sv is computed from.

set_property -dict { PACKAGE_PIN U22   IOSTANDARD LVCMOS33 } [get_ports { clk_in1_0 }]
create_clock -add -name sys_clk_pin -period 20.00 -waveform {0 10} [get_ports { clk_in1_0 }]

# ---------------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------------
# ext_reset_in_0 is active-high and is synchronized to clk_in1_0 inside
# ecc_uart_top.sv (see the reset-synchronizer comment there) before it
# touches anything else, so it does not need to meet a clocked timing path.
set_property -dict { PACKAGE_PIN P4  IOSTANDARD LVCMOS33 } [get_ports { ext_reset_in_0 }]
set_false_path -from [get_ports { ext_reset_in_0 }]

# ---------------------------------------------------------------------------
# UART -- 115200 baud, 8-N-1 (see docs/UART_PROTOCOL.md)
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E26   IOSTANDARD LVCMOS33 } [get_ports { TXD_0 }]
set_property -dict { PACKAGE_PIN E25   IOSTANDARD LVCMOS33 } [get_ports { RXD_0 }]

# UART is asynchronous to the system clock and, at 115200 baud, orders of
# magnitude slower -- there is no meaningful setup/hold relationship to
# check against sys_clk_pin, so both pins are false paths rather than
# constrained to it.
set_false_path -to   [get_ports { TXD_0 }]
set_false_path -from [get_ports { RXD_0 }]

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
