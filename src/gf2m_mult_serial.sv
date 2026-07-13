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
// File        : gf2m_mult_serial.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Shift-and-add GF(2^233) multiplier. One bit of a per
//               cycle, W cycles total. Used by every other module here.
// =============================================================================
`timescale 1ns / 1ps

module gf2m_mult_serial
  import gf2m_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,
  input  logic          start,
  input  logic [W-1:0]  a_in,
  input  logic [W-1:0]  b_in,
  output logic          busy,
  output logic          done,
  output logic [W-1:0]  product
);

  typedef enum logic [1:0] {IDLE, RUN, DONE_ST} state_t;
  state_t state;

  logic [W-1:0]        a_r, b_r, c_r;
  logic [$clog2(W):0]  cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= IDLE;
      a_r     <= '0;
      b_r     <= '0;
      c_r     <= '0;
      cnt     <= '0;
      done    <= 1'b0;
      product <= '0;
    end else begin
      done <= 1'b0;
      unique case (state)
        IDLE: begin
          if (start) begin
            c_r   <= a_in[0] ? b_in : '0;
            b_r   <= xtimes(b_in);
            a_r   <= a_in >> 1;
            cnt   <= 1;
            state <= RUN;
          end
        end

        RUN: begin
          if (a_r[0])
            c_r <= c_r ^ b_r;

          if (cnt == W-1) begin
            state <= DONE_ST;
          end else begin
            b_r <= xtimes(b_r);
            a_r <= a_r >> 1;
            cnt <= cnt + 1'b1;
          end
        end

        DONE_ST: begin
          product <= c_r;
          done    <= 1'b1;
          state   <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

  assign busy = (state != IDLE);

endmodule
