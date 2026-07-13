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
// File        : uart_tx.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Minimal 8-N-1 UART transmitter. Pulse tx_start with
//               data_in held stable, wait for tx_busy to fall.
// =============================================================================
`timescale 1ns / 1ps

module uart_tx #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tx_start,
    input  logic [7:0] data_in,
    output logic       tx_busy,
    output logic       tx_line
);

    localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;

    typedef enum logic [1:0] {IDLE, START_BIT, DATA_BITS, STOP_BIT} state_t;
    state_t state;

    logic [7:0] data_r;
    logic [2:0] bit_idx;
    logic [$clog2(CLKS_PER_BIT+1)-1:0] clk_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            data_r  <= '0;
            bit_idx <= '0;
            clk_cnt <= '0;
            tx_line <= 1'b1; // idle line is high
        end else begin
            unique case (state)
                IDLE: begin
                    tx_line <= 1'b1;
                    if (tx_start) begin
                        data_r  <= data_in;
                        clk_cnt <= '0;
                        state   <= START_BIT;
                    end
                end

                START_BIT: begin
                    tx_line <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        bit_idx <= '0;
                        state   <= DATA_BITS;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DATA_BITS: begin
                    tx_line <= data_r[bit_idx]; // LSB first
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
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
                    tx_line <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        state   <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign tx_busy = (state != IDLE);

endmodule
