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
// File        : tb_ld_point_add.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Modified Lopez-Dahab point addition vs. the Python golden model
// =============================================================================
//
// Checks ld_point_add against G + 2G computed by the Python golden model:
// P = G (Z1 = 1, structurally guaranteed by the port list),
// Q = 2G (general Z2, taken straight from ld_point_double's own output).

`timescale 1ns/1ps

module tb_ld_point_add;
  import gf2m_pkg::*;

  logic         clk = 0;
  logic         rst_n;
  logic         start;
  logic [W-1:0] X1_in, Y1_in, X2_in, Y2_in, Z2_in;
  logic         busy, done;
  logic [W-1:0] X3_out, Y3_out, Z3_out;

  int errors = 0;

  ld_point_add dut (
    .clk, .rst_n, .start, .X1_in, .Y1_in, .X2_in, .Y2_in, .Z2_in,
    .busy, .done, .X3_out, .Y3_out, .Z3_out
  );

  always #5 clk = ~clk;

  // G
  localparam logic [W-1:0] GX = 233'h0fac9dfcbac8313bb2139f1bb755fef65bc391f8b36f8f8eb7371fd558b;
  localparam logic [W-1:0] GY = 233'h1006a08a41903350678e58528bebf8a0beff867a7ca36716f7e01f81052;

  // 2G in LD projective coordinates (Q, general Z), from the Python model
  localparam logic [W-1:0] Q2X = 233'h017879e3975bc39ca44a3790beacc68d0aabf82f07d8e81f53b364e69b7;
  localparam logic [W-1:0] Q2Y = 233'h0c82bd1c103aaccb0bb3fdd1ac18b451b874b7f1f9060bd58c623e6f248;
  localparam logic [W-1:0] Q2Z = 233'h0df363367f225632bf562e6f8871c6d98b537780dfad1f3b68accc9afab;

  // Expected G + 2G = 3G, in LD projective coordinates
  localparam logic [W-1:0] EXP_X3 = 233'h147c656507c1714a8a2c5c5f0d22c9cf90da91049f28428c5438102ad6f;
  localparam logic [W-1:0] EXP_Y3 = 233'h1e3f0c03b8d98bbd3a4645db25c3162754401c3ff63c71f0d4d4e6d009a;
  localparam logic [W-1:0] EXP_Z3 = 233'h0e7ad1111868ba5b043e487c976974ad4686aaa69eed525b910a8a64154;

  initial begin
    rst_n = 0;
    start = 0;
    X1_in = '0; Y1_in = '0; X2_in = '0; Y2_in = '0; Z2_in = '0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    @(posedge clk);
    X1_in = GX;  Y1_in = GY;   // P = G, Z1 = 1 (implicit)
    X2_in = Q2X; Y2_in = Q2Y; Z2_in = Q2Z; // Q = 2G
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;
    wait (done == 1'b1);
    @(posedge clk);

    if (X3_out !== EXP_X3) begin
      $display("[FAIL] (G+2G).X: got %h expected %h", X3_out, EXP_X3);
      errors++;
    end else $display("[PASS] (G+2G).X: %h", X3_out);

    if (Y3_out !== EXP_Y3) begin
      $display("[FAIL] (G+2G).Y: got %h expected %h", Y3_out, EXP_Y3);
      errors++;
    end else $display("[PASS] (G+2G).Y: %h", Y3_out);

    if (Z3_out !== EXP_Z3) begin
      $display("[FAIL] (G+2G).Z: got %h expected %h", Z3_out, EXP_Z3);
      errors++;
    end else $display("[PASS] (G+2G).Z: %h", Z3_out);

    if (errors == 0)
      $display("\nALL TESTS PASSED (ld_point_add)");
    else
      $display("\n%0d TEST(S) FAILED (ld_point_add)", errors);

    $finish;
  end
endmodule
