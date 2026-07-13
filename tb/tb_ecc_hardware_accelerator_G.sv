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
// File        : tb_ecc_hardware_accelerator_G.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Scalar-multiplier core: small scalars + k=0, vs. known-answer vectors
// =============================================================================
//
// End-to-end test: k*G for several scalars, checked against the known-
// answer vectors in docs/KNOWN_ANSWER_TESTS.md (produced independently by
// the Python golden model). Also exercises k=0 (point at infinity).

`timescale 1ns/1ps

module tb_ecc_hardware_accelerator_G;
  import gf2m_pkg::*;

  localparam int KBITS = W;
  localparam int KLEN_W = $clog2(KBITS+1);

  logic              clk = 0;
  logic              rst_n;
  logic              start;
  logic [KBITS-1:0]  k_in;
  logic [KLEN_W-1:0] k_len;
  logic [W-1:0]      Px_in, Py_in;
  logic              busy, done, result_is_infinity;
  logic [W-1:0]      Qx_out, Qy_out;

  int errors = 0;

  ecc_hardware_accelerator_G #(.KBITS(KBITS)) dut (
    .clk, .rst_n, .start, .k_in, .k_len, .Px_in, .Py_in,
    .busy, .done, .result_is_infinity, .Qx_out, .Qy_out
  );

  always #5 clk = ~clk;

  localparam logic [W-1:0] GX = 233'h0fac9dfcbac8313bb2139f1bb755fef65bc391f8b36f8f8eb7371fd558b;
  localparam logic [W-1:0] GY = 233'h1006a08a41903350678e58528bebf8a0beff867a7ca36716f7e01f81052;

  task automatic run_case(input logic [KBITS-1:0] k, input int len,
                           input logic [W-1:0] exp_x, input logic [W-1:0] exp_y,
                           input string name);
    begin
      @(posedge clk);
      k_in  = k;
      k_len = len[KLEN_W-1:0];
      Px_in = GX;
      Py_in = GY;
      start = 1'b1;
      @(posedge clk);
      start = 1'b0;
      wait (done == 1'b1);
      @(posedge clk);
      if (result_is_infinity) begin
        $display("[FAIL] %s: got point at infinity, expected a finite point", name);
        errors++;
      end else if (Qx_out !== exp_x || Qy_out !== exp_y) begin
        $display("[FAIL] %s: got (%h, %h) expected (%h, %h)",
                  name, Qx_out, Qy_out, exp_x, exp_y);
        errors++;
      end else begin
        $display("[PASS] %s: (%h, %h)", name, Qx_out, Qy_out);
      end
    end
  endtask

  initial begin
    rst_n = 0;
    start = 0;
    k_in = '0; k_len = '0; Px_in = '0; Py_in = '0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    run_case(233'd2, 2,
      233'h0845fd61638bac7d9e109a67a1f7047dc0fd9a5488a8468364bdc592aad,
      233'h01b1420774abba2587c83900984765a8a85d776325fc39cc7823d734660,
      "2*G");

    run_case(233'd3, 2,
      233'h080f50a330911bd753a76364595b9f0158c4d02a85cc0e3fb6ea0aef9ff,
      233'h017a49033f12eb52675e98e6432cc27104bd5c42bcbe3daf76901c9b8743,
      "3*G");

    run_case(233'd5, 3,
      233'h194ed0ca60c85e59e7c4b69f30c6304a9f485f45032b871c4a23ffec8c1,
      233'h0a52f9459c2fab39c214061e272e1e115e1e01a98e4f09cd5a85d2698c6,
      "5*G");

    run_case(233'd12345, 14,
      233'h171cdbf80d4cf050fafeea2b01039d6ae34aca712ff64ec8037a8496138,
      233'h13449a47f49a1f7bfbafa5ed0d36958e5f36d3be206adf07262f79bc2e1,
      "12345*G");

    // k = 0 -> point at infinity
    @(posedge clk);
    k_in = '0; k_len = '0; Px_in = GX; Py_in = GY;
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;
    wait (done == 1'b1);
    @(posedge clk);
    if (!result_is_infinity) begin
      $display("[FAIL] 0*G: expected point at infinity");
      errors++;
    end else begin
      $display("[PASS] 0*G: point at infinity");
    end

    if (errors == 0)
      $display("\nALL TESTS PASSED (ecc_hardware_accelerator_G)");
    else
      $display("\n%0d TEST(S) FAILED (ecc_hardware_accelerator_G)", errors);

    $finish;
  end
endmodule
