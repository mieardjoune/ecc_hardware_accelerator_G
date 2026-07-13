// Copyright 2026 M. I. E. ARDJOUNE
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//
// =============================================================================
// File        : uart_rx.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Minimal 8-N-1 UART receiver, counterpart to uart_tx.sv.
//               rx_valid pulses one clock when a byte is ready.
// =============================================================================
`timescale 1ns / 1ps

module uart_rx #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx_line,
    output logic        rx_valid,
    output logic [7:0]  rx_data
);

    localparam int CLKS_PER_BIT     = CLK_FREQ_HZ / BAUD_RATE;
    localparam int CLKS_PER_HALFBIT = CLKS_PER_BIT / 2;

    // rx_line is an async input, synchronize it
    logic rx_sync_0, rx_sync_1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync_0 <= 1'b1;
            rx_sync_1 <= 1'b1;
        end else begin
            rx_sync_0 <= rx_line;
            rx_sync_1 <= rx_sync_0;
        end
    end

    typedef enum logic [1:0] {IDLE, START_BIT, DATA_BITS, STOP_BIT} state_t;
    state_t state;

    logic [7:0] data_r;
    logic [2:0] bit_idx;
    logic [$clog2(CLKS_PER_BIT+1)-1:0] clk_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            data_r   <= '0;
            bit_idx  <= '0;
            clk_cnt  <= '0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;

            unique case (state)
                IDLE: begin
                    if (rx_sync_1 == 1'b0) begin // falling edge -> start bit
                        clk_cnt <= '0;
                        state   <= START_BIT;
                    end
                end

                START_BIT: begin
                    // sample the middle of the start bit
                    if (clk_cnt == CLKS_PER_HALFBIT-1) begin
                        if (rx_sync_1 == 1'b0) begin
                            clk_cnt <= '0;
                            bit_idx <= '0;
                            state   <= DATA_BITS;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DATA_BITS: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt         <= '0;
                        data_r[bit_idx] <= rx_sync_1;
                        if (bit_idx == 3'd7) begin
                            state <= STOP_BIT;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                STOP_BIT: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        rx_data  <= data_r;
                        rx_valid <= 1'b1;
                        clk_cnt  <= '0;
                        state    <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
