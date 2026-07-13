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
// File        : tb_gf2m_mult_serial.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : GF(2^233) serial multiplier vs. known-answer vectors
// =============================================================================
//
// Checks gf2m_mult_serial against vectors from python_model/, including
// one that matches a hand-worked multiplication example.

`timescale 1ns/1ps

module tb_gf2m_mult_serial;

  import gf2m_pkg::*;

  logic         clk = 0;
  logic         rst_n;
  logic         start;
  logic [W-1:0] a_in, b_in;
  logic         busy, done;
  logic [W-1:0] product;

  int errors = 0;

  gf2m_mult_serial dut (
    .clk, .rst_n, .start, .a_in, .b_in, .busy, .done, .product
  );

  always #5 clk = ~clk;

  task automatic run_case(input logic [W-1:0] a, input logic [W-1:0] b,
                           input logic [W-1:0] expected, input string name);
    begin
      @(posedge clk);
      a_in  = a;
      b_in  = b;
      start = 1'b1;
      @(posedge clk);
      start = 1'b0;
      wait (done == 1'b1);
      @(posedge clk); // let `product` settle (registered on DONE_ST)
      if (product !== expected) begin
        $display("[FAIL] %s: got %h expected %h", name, product, expected);
        errors++;
      end else begin
        $display("[PASS] %s: %h", name, product);
      end
    end
  endtask

  initial begin
    rst_n = 0;
    start = 0;
    a_in  = '0;
    b_in  = '0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    // known-answer vector: X * Y
    run_case(
      233'h17232ba853a7e731af129f22ff4149563a419c26bf50a4c9d6eefad6125,
      233'h1db537dece819b7f70f555a67c427a8cd9bf18aeb9b56e0c11056fae6a3,
      233'h02db9c59a4bbf539e65d0174b12a0c30657655eeacb017a3d4466d2392e,
      "X*Y"
    );

    // Identity and zero
    run_case(233'hABCDEF, 233'h1, 233'hABCDEF, "a*1 == a");
    run_case(233'hABCDEF, 233'h0, 233'h0,      "a*0 == 0");

    // X^2 via multiplier (cross-check against dedicated squarer results)
    run_case(
      233'h17232ba853a7e731af129f22ff4149563a419c26bf50a4c9d6eefad6125,
      233'h17232ba853a7e731af129f22ff4149563a419c26bf50a4c9d6eefad6125,
      233'h113bcafec38a1e9f284bec901039e7f0d4bc3b7a1ebd2526abed8419d34,
      "X*X == X^2"
    );

    if (errors == 0)
      $display("\nALL TESTS PASSED (gf2m_mult_serial)");
    else
      $display("\n%0d TEST(S) FAILED (gf2m_mult_serial)", errors);

    $finish;
  end

endmodule
