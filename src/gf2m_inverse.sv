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
// File        : gf2m_inverse.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Itoh-Tsujii inversion: a^-1 = a^(2^233-2), using about 11
//               multiplies plus squarings instead of ~232 multiplies.
// =============================================================================
`timescale 1ns / 1ps
//
// s <- a, k <- 1                      (s = a^(2^k - 1))
// for each bit of 232, MSB first, skipping the leading 1:
//     s <- s^(2^k) * s, k <- 2k        (double)
//     if bit == 1:
//         s <- s^2 * a, k <- k+1       (increment)
// return s^2                           (= a^(2^233-2) = a^-1)
//
// s^(2^k) is k squarings in a row (combinational). The bit pattern of
// 232 is fixed.

module gf2m_inverse
  import gf2m_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,
  input  logic          start,
  input  logic [W-1:0]  a_in,
  output logic          busy,
  output logic          done,
  output logic [W-1:0]  inv_out
);

  localparam int M_MINUS_1 = W - 1; // 232
  localparam int NBITS = $clog2(M_MINUS_1 + 1);
  logic [NBITS-1:0] bits;
  assign bits = M_MINUS_1[NBITS-1:0];

  typedef enum logic [3:0] {
    IDLE,
    DBL_FROB_START, DBL_FROB_WAIT,
    DBL_MUL_START,  DBL_MUL_WAIT,
    INCR_SQ,
    INCR_MUL_START, INCR_MUL_WAIT,
    FINAL_SQ,
    DONE_ST
  } state_t;
  state_t state;

  logic [W-1:0] a_r;
  logic [W-1:0] s_r;
  logic [W-1:0] s_frob_r;
  logic [$clog2(W)+1:0] k_r;
  logic [$clog2(W)+1:0] frob_cnt;
  int bit_idx;
  logic mul_start;
  logic [W-1:0] mul_a, mul_b;
  logic mul_busy, mul_done;
  logic [W-1:0] mul_product;

  gf2m_mult_serial u_mult (
    .clk, .rst_n,
    .start   (mul_start),
    .a_in    (mul_a),
    .b_in    (mul_b),
    .busy    (mul_busy),
    .done    (mul_done),
    .product (mul_product)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= IDLE;
      a_r       <= '0;
      s_r       <= '0;
      s_frob_r  <= '0;
      k_r       <= '0;
      frob_cnt  <= '0;
      bit_idx   <= 0;
      mul_start <= 1'b0;
      mul_a     <= '0;
      mul_b     <= '0;
      done      <= 1'b0;
      inv_out   <= '0;
    end else begin
      mul_start <= 1'b0;
      done      <= 1'b0;

      unique case (state)
        IDLE: begin
          if (start) begin
            a_r     <= a_in;
            s_r     <= a_in;
            k_r     <= 1;
            bit_idx <= NBITS - 2; // skip the leading 1 bit
            state   <= DBL_FROB_START;
          end
        end

        DBL_FROB_START: begin
          s_frob_r <= s_r;
          frob_cnt <= k_r;
          state    <= DBL_FROB_WAIT;
        end

        DBL_FROB_WAIT: begin
          if (frob_cnt == 0) begin
            mul_a     <= s_frob_r;
            mul_b     <= s_r;
            mul_start <= 1'b1;
            state     <= DBL_MUL_START;
          end else begin
            s_frob_r <= gf_square(s_frob_r);
            frob_cnt <= frob_cnt - 1'b1;
          end
        end

        DBL_MUL_START: begin
          if (mul_done) begin
            s_r   <= mul_product;
            k_r   <= k_r << 1;
            state <= state_t'((bits[bit_idx] == 1'b1) ? INCR_SQ : DBL_MUL_WAIT);
          end
        end

        DBL_MUL_WAIT: begin
          if (bit_idx == 0)
            state <= FINAL_SQ;
          else begin
            bit_idx <= bit_idx - 1;
            state   <= DBL_FROB_START;
          end
        end

        INCR_SQ: begin
          mul_a     <= gf_square(s_r);
          mul_b     <= a_r;
          mul_start <= 1'b1;
          state     <= INCR_MUL_START;
        end

        INCR_MUL_START: begin
          if (mul_done) begin
            s_r   <= mul_product;
            k_r   <= k_r + 1'b1;
            state <= INCR_MUL_WAIT;
          end
        end

        INCR_MUL_WAIT: begin
          if (bit_idx == 0)
            state <= FINAL_SQ;
          else begin
            bit_idx <= bit_idx - 1;
            state   <= DBL_FROB_START;
          end
        end

        FINAL_SQ: begin
          inv_out <= gf_square(s_r);
          state   <= DONE_ST;
        end

        DONE_ST: begin
          done  <= 1'b1;
          state <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

  assign busy = (state != IDLE);

endmodule
