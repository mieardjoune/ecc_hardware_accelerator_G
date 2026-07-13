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
// File        : 00_gf2m_pkg.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : GF(2^233) constants and helper functions for curve
//               sect233r1. Numbered prefix so a plain file glob compiles
//               this before anything that imports it.
// =============================================================================
`timescale 1ns / 1ps

package gf2m_pkg;

  localparam int W = 233;

  // f(x) = x^233 + x^74 + 1, low part (bit 233 handled separately in xtimes)
  localparam logic [W-1:0] REDUCTION_LOW = (W'(1) << 74) | W'(1);

  // a2^2 = a. Curve has a = 1, so a2 = 1.
  localparam logic [W-1:0] A2 = W'(1);

  // Multiply by x and reduce, one step of the shift-and-add multiplier.
  function automatic logic [W-1:0] xtimes(input logic [W-1:0] p);
    logic [W:0] shifted;
    begin
      shifted = {p, 1'b0};
      if (shifted[W])
        xtimes = shifted[W-1:0] ^ REDUCTION_LOW;
      else
        xtimes = shifted[W-1:0];
    end
  endfunction

  // Squaring is linear in this field, so it's a bit spread plus a
  // reduction instead of a full multiply.
  function automatic logic [W-1:0] gf_square(input logic [W-1:0] a);
    logic [2*W-2:0] wide;
    int i;
    begin
      wide = '0;
      for (i = 0; i < W; i++) begin
        wide[2*i] = a[i];
      end
      for (i = 2*W-2; i >= W; i--) begin
        if (wide[i]) begin
          wide[i]      = 1'b0;
          wide[i-W]    = wide[i-W]    ^ 1'b1;
          wide[i-W+74] = wide[i-W+74] ^ 1'b1;
        end
      end
      gf_square = wide[W-1:0];
    end
  endfunction

  // a2 is 0 or 1 here, so multiplying by it is free.
  function automatic logic [W-1:0] mul_a2(input logic [W-1:0] x);
    if (A2 == W'(1))
      mul_a2 = x;
    else if (A2 == '0)
      mul_a2 = '0;
    else
      mul_a2 = 'x;
  endfunction

endpackage
