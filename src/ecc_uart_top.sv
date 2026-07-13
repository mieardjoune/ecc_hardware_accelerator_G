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
// File        : ecc_uart_top.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Top module for the QMTECH Artix-7 board. Wraps
//               ecc_hardware_accelerator_G in a fixed-length UART protocol: send a
//               scalar k, read back k*G. See docs/UART_PROTOCOL.md.
// =============================================================================
`timescale 1ns / 1ps
//
// Port names match constraints/physical.xdc.
//   clk_in1_0       board oscillator (see README.md for frequency)
//   ext_reset_in_0  external reset, active high
//   TXD_0 / RXD_0   UART
//
// Host sends 30 bytes (k, big-endian, top 7 bits zero). FPGA replies
// with 61 bytes: 1 status byte (0x00 ok / 0x01 infinity), then Qx and Qy
// in the same 30-byte encoding. Response length never changes. After
// replying the FPGA goes straight back to waiting for the next scalar.

module ecc_uart_top
  import gf2m_pkg::*;
#(
    parameter int CLK_FREQ_HZ = 50_000_000, // match your board's oscillator
    parameter int BAUD_RATE   = 115_200
)(
    input  logic clk_in1_0,
    input  logic ext_reset_in_0,
    output logic TXD_0,
    input  logic RXD_0
);

    // async assert, sync de-assert reset
    logic [1:0] rst_sync;
    logic       rst_n;

    always_ff @(posedge clk_in1_0 or posedge ext_reset_in_0) begin
        if (ext_reset_in_0)
            rst_sync <= 2'b11;
        else
            rst_sync <= {rst_sync[0], 1'b0};
    end
    assign rst_n = ~rst_sync[1];

    logic       tx_start, tx_busy;
    logic [7:0] tx_data;
    logic       rx_valid;
    logic [7:0] rx_data;

    uart_tx #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_uart_tx (
        .clk(clk_in1_0), .rst_n,
        .tx_start, .data_in(tx_data), .tx_busy, .tx_line(TXD_0)
    );

    uart_rx #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_uart_rx (
        .clk(clk_in1_0), .rst_n,
        .rx_line(RXD_0), .rx_valid, .rx_data
    );

    // fixed base point G, k_len always 233 to keep the protocol fixed length
    localparam logic [W-1:0] GX =
        233'h0fac9dfcbac8313bb2139f1bb755fef65bc391f8b36f8f8eb7371fd558b;
    localparam logic [W-1:0] GY =
        233'h1006a08a41903350678e58528bebf8a0beff867a7ca36716f7e01f81052;

    localparam int NBYTES   = (W + 7) / 8;      // 30 bytes hold 240 bits
    localparam int PAD_BITS = 8*NBYTES - W;      // 7 unused top bits

    logic                       ecc_start, ecc_busy, ecc_done, ecc_inf;
    logic [W-1:0]               ecc_qx, ecc_qy;
    logic [$clog2(W+1)-1:0]     k_len_const;
    assign k_len_const = W[$clog2(W+1)-1:0];

    logic [W-1:0] k_latched;

    ecc_hardware_accelerator_G #(.KBITS(W)) u_ecc (
        .clk(clk_in1_0), .rst_n,
        .start(ecc_start),
        .k_in(k_latched),
        .k_len(k_len_const),
        .Px_in(GX), .Py_in(GY),
        .busy(ecc_busy), .done(ecc_done),
        .result_is_infinity(ecc_inf),
        .Qx_out(ecc_qx), .Qy_out(ecc_qy)
    );

    typedef enum logic [2:0] {
        RX_K, RUN_ECC, LOAD_RESPONSE, TX_BYTE_START, TX_BYTE_WAIT
    } state_t;
    state_t state;

    logic [$clog2(NBYTES+1)-1:0]        rx_byte_cnt;
    logic [8*NBYTES-1:0]                rx_shift; // 240-bit big-endian scalar
    logic [8*NBYTES-1:0]                rx_shift_next;

    assign rx_shift_next = {rx_shift[8*NBYTES-9:0], rx_data};

    localparam int RESP_BYTES = 1 + 2*NBYTES; // status + Qx + Qy = 61 bytes
    logic [8*RESP_BYTES-1:0]            tx_shift;
    logic [$clog2(RESP_BYTES+1)-1:0]    tx_byte_cnt;

    always_ff @(posedge clk_in1_0 or negedge rst_n) begin
        if (!rst_n) begin
            state       <= RX_K;
            rx_byte_cnt <= '0;
            rx_shift    <= '0;
            k_latched   <= '0;
            ecc_start   <= 1'b0;
            tx_shift    <= '0;
            tx_byte_cnt <= '0;
            tx_start    <= 1'b0;
            tx_data     <= '0;
        end else begin
            ecc_start <= 1'b0;
            tx_start  <= 1'b0;

            unique case (state)
                RX_K: begin
                    if (rx_valid) begin
                        rx_shift <= rx_shift_next;
                        if (rx_byte_cnt == NBYTES-1) begin
                            rx_byte_cnt <= '0;
                            k_latched <= rx_shift_next[W-1:0];
                            ecc_start <= 1'b1;
                            state     <= RUN_ECC;
                        end else begin
                            rx_byte_cnt <= rx_byte_cnt + 1'b1;
                        end
                    end
                end

                RUN_ECC: begin
                    if (ecc_done) begin
                        state <= LOAD_RESPONSE;
                    end
                end

                LOAD_RESPONSE: begin
                    tx_shift <= {
                        (ecc_inf ? 8'h01 : 8'h00),
                        (ecc_inf ? {W{1'b0}} : {{PAD_BITS{1'b0}}, ecc_qx}),
                        (ecc_inf ? {W{1'b0}} : {{PAD_BITS{1'b0}}, ecc_qy})
                    };
                    tx_byte_cnt <= '0;
                    state       <= TX_BYTE_START;
                end

                TX_BYTE_START: begin
                    tx_data  <= tx_shift[8*RESP_BYTES-1 -: 8];
                    tx_start <= 1'b1;
                    state    <= TX_BYTE_WAIT;
                end

                TX_BYTE_WAIT: begin
                    if (tx_busy) begin
                        // wait for uart_tx to finish this byte
                    end else if (!tx_start) begin
                        tx_shift <= tx_shift << 8;
                        if (tx_byte_cnt == RESP_BYTES-1) begin
                            state <= RX_K;
                        end else begin
                            tx_byte_cnt <= tx_byte_cnt + 1'b1;
                            state       <= TX_BYTE_START;
                        end
                    end
                end

                default: state <= RX_K;
            endcase
        end
    end

endmodule
