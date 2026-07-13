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
// File        : tb_ecc_hardware_accelerator_G_full_order.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Scalar-multiplier core: full 233-bit scalars ((n-1)*G, n*G)
// =============================================================================
//
// Heavier end-to-end check: (n-1)*G should equal -G = (Gx, Gx+Gy) for this
// curve. Exercises all 233 bits of a real scalar (worst case for the
// loop), unlike the small scalars in tb_ecc_hardware_accelerator_G.sv.

`timescale 1ns/1ps

module tb_ecc_hardware_accelerator_G_full_order;
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

  ecc_hardware_accelerator_G #(.KBITS(KBITS)) dut (
    .clk, .rst_n, .start, .k_in, .k_len, .Px_in, .Py_in,
    .busy, .done, .result_is_infinity, .Qx_out, .Qy_out
  );

  always #5 clk = ~clk;

  localparam logic [W-1:0] GX = 233'h0fac9dfcbac8313bb2139f1bb755fef65bc391f8b36f8f8eb7371fd558b;
  localparam logic [W-1:0] GY = 233'h1006a08a41903350678e58528bebf8a0beff867a7ca36716f7e01f81052;
  // n - 1
  localparam logic [W-1:0] K  = 233'h1000000000000000000000000000013e974e72f8a6922031d2603cfe0d6;
  // -G = (Gx, Gx + Gy)
  localparam logic [W-1:0] EXP_X = GX;
  localparam logic [W-1:0] EXP_Y = GX ^ GY;

  // n
  localparam logic [W-1:0] N_ORDER = 233'h1000000000000000000000000000013e974e72f8a6922031d2603cfe0d7;

  int errors = 0;

  initial begin
    rst_n = 0; start = 0;
    k_in = '0; k_len = '0; Px_in = '0; Py_in = '0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    @(posedge clk);
    k_in  = K;
    k_len = 233;
    Px_in = GX;
    Py_in = GY;
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;
    wait (done == 1'b1);
    @(posedge clk);

    if (result_is_infinity) begin
      $display("[FAIL] (n-1)*G: got point at infinity");
      errors++;
    end else if (Qx_out !== EXP_X || Qy_out !== EXP_Y) begin
      $display("[FAIL] (n-1)*G: got (%h, %h) expected (%h, %h)",
                Qx_out, Qy_out, EXP_X, EXP_Y);
      errors++;
    end else begin
      $display("[PASS] (n-1)*G == -G: (%h, %h)", Qx_out, Qy_out);
    end

    // n * G should be the point at infinity.
    @(posedge clk);
    k_in  = N_ORDER;
    k_len = 233;
    Px_in = GX;
    Py_in = GY;
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;
    wait (done == 1'b1);
    @(posedge clk);

    if (!result_is_infinity) begin
      $display("[FAIL] n*G: expected point at infinity, got (%h, %h)", Qx_out, Qy_out);
      errors++;
    end else begin
      $display("[PASS] n*G == point at infinity");
    end

    if (errors == 0)
      $display("\nALL TESTS PASSED (ecc_hardware_accelerator_G, full-order scalar)");
    else
      $display("\n%0d TEST(S) FAILED", errors);

    $finish;
  end
endmodule
