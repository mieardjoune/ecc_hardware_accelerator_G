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
// File        : tb_gf2m_square.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Combinational squarer vs. the Python golden model
// =============================================================================
//
// Checks the combinational bit-spread squarer against values independently
// computed by python_model/ecc_gf2m/gf2m.py.

`timescale 1ns/1ps

module tb_gf2m_square;
  import gf2m_pkg::*;

  int errors = 0;

  task automatic check(input logic [W-1:0] a, input logic [W-1:0] expected,
                        input string name);
    logic [W-1:0] got;
    begin
      got = gf_square(a);
      if (got !== expected) begin
        $display("[FAIL] %s: got %h expected %h", name, got, expected);
        errors++;
      end else begin
        $display("[PASS] %s: %h", name, got);
      end
    end
  endtask

  initial begin
    check(233'h17232ba853a7e731af129f22ff4149563a419c26bf50a4c9d6eefad6125,
          233'h113bcafec38a1e9f284bec901039e7f0d4bc3b7a1ebd2526abed8419d34,
          "X^2");
    check(233'h1db537dece819b7f70f555a67c427a8cd9bf18aeb9b56e0c11056fae6a3,
          233'h068f05b49e5578168c45662867bf7802be523e250d9f60f5af90d421ef3,
          "Y^2");
    check(233'h1, 233'h1, "1^2 == 1");
    check(233'h0, 233'h0, "0^2 == 0");

    if (errors == 0)
      $display("\nALL TESTS PASSED (gf2m_square)");
    else
      $display("\n%0d TEST(S) FAILED (gf2m_square)", errors);
    $finish;
  end
endmodule
