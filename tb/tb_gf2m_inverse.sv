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
// File        : tb_gf2m_inverse.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Itoh-Tsujii inversion vs. known-answer vectors
// =============================================================================
//
// Checks gf2m_inverse against a known Y^-1 vector from python_model/.

`timescale 1ns/1ps

module tb_gf2m_inverse;
  import gf2m_pkg::*;

  logic         clk = 0;
  logic         rst_n;
  logic         start;
  logic [W-1:0] a_in;
  logic         busy, done;
  logic [W-1:0] inv_out;

  int errors = 0;

  gf2m_inverse dut (.clk, .rst_n, .start, .a_in, .busy, .done, .inv_out);

  always #5 clk = ~clk;

  task automatic run_case(input logic [W-1:0] a, input logic [W-1:0] expected,
                           input string name);
    begin
      @(posedge clk);
      a_in  = a;
      start = 1'b1;
      @(posedge clk);
      start = 1'b0;
      wait (done == 1'b1);
      @(posedge clk);
      if (inv_out !== expected) begin
        $display("[FAIL] %s: got %h expected %h", name, inv_out, expected);
        errors++;
      end else begin
        $display("[PASS] %s: %h", name, inv_out);
      end
    end
  endtask

  initial begin
    rst_n = 0;
    start = 0;
    a_in  = '0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    // Y^-1, from python_model/
    run_case(
      233'h1db537dece819b7f70f555a67c427a8cd9bf18aeb9b56e0c11056fae6a3,
      233'h036f0932fbd15fbd39fa1dc9d1462fcb362fbb6d6d716cdf5cf5ef9fae3,
      "Y^-1"
    );

    run_case(233'h1, 233'h1, "1^-1 == 1");

    if (errors == 0)
      $display("\nALL TESTS PASSED (gf2m_inverse)");
    else
      $display("\n%0d TEST(S) FAILED (gf2m_inverse)", errors);

    $finish;
  end
endmodule
