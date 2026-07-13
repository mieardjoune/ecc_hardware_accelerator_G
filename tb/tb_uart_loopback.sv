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
// File        : tb_uart_loopback.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : uart_tx -> uart_rx loopback sanity check
// =============================================================================
//
// Wires uart_tx straight into uart_rx (tx_line -> rx_line) and checks that
// a handful of bytes round-trip correctly. Uses a fast, exactly-integer
// clock/baud ratio (CLKS_PER_BIT = 4) purely to keep simulation time
// short; the RTL itself is unchanged from the CLK_FREQ_HZ=50_000_000,
// BAUD_RATE=115_200 configuration used on real hardware (see
// projects/ecc_hardware_accelerator_G/README.md).

`timescale 1ns/1ps

module tb_uart_loopback;

    localparam int CLK_FREQ_HZ = 400_000;
    localparam int BAUD_RATE   = 100_000; // CLKS_PER_BIT = 4

    logic clk = 0;
    logic rst_n;

    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_busy;
    logic       tx_line;

    logic       rx_valid;
    logic [7:0] rx_data;

    int errors = 0;

    always #5 clk = ~clk;

    uart_tx #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_tx (
        .clk, .rst_n, .tx_start, .data_in(tx_data), .tx_busy, .tx_line
    );

    uart_rx #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk, .rst_n, .rx_line(tx_line), .rx_valid, .rx_data
    );

    task automatic send_and_check(input logic [7:0] b);
        begin
            @(posedge clk);
            tx_data  = b;
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0;
            wait (rx_valid == 1'b1);
            if (rx_data !== b) begin
                $display("[FAIL] sent %h, received %h", b, rx_data);
                errors++;
            end else begin
                $display("[PASS] byte %h round-tripped correctly", b);
            end
            wait (tx_busy == 1'b0);
        end
    endtask

    initial begin
        rst_n = 0;
        tx_start = 0;
        tx_data  = '0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        send_and_check(8'h00);
        send_and_check(8'hFF);
        send_and_check(8'hA5);
        send_and_check(8'h5A);
        send_and_check(8'h37);

        if (errors == 0)
            $display("\nALL TESTS PASSED (uart loopback)");
        else
            $display("\n%0d TEST(S) FAILED (uart loopback)", errors);

        $finish;
    end

endmodule
