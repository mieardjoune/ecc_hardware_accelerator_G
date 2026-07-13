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
// File        : ld_point_double.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Modified Lopez-Dahab point doubling. 2P = (X3:Y3:Z3)
//               from P = (X1:Y1:Z1), Z1 arbitrary. See docs/MATH.md.
// =============================================================================
`timescale 1ns / 1ps
//
//   S  = X1^2
//   U  = S + Y1
//   T  = X1*Z1
//   Z3 = T^2
//   T  = U*T
//   X3 = U^2 + T + a2*Z3
//   Y3 = (Z3 + T)*X3 + S^2*Z3

module ld_point_double
  import gf2m_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,
  input  logic          start,
  input  logic [W-1:0]  X1_in,
  input  logic [W-1:0]  Y1_in,
  input  logic [W-1:0]  Z1_in,
  output logic          busy,
  output logic          done,
  output logic [W-1:0]  X3_out,
  output logic [W-1:0]  Y3_out,
  output logic [W-1:0]  Z3_out
);

  typedef enum logic [3:0] {
    IDLE,
    ST_S_U,             // S = X1^2 ; U = S + Y1
    ST_MUL1_START, ST_MUL1_WAIT,   // T = X1*Z1
    ST_Z3,              // Z3 = T^2
    ST_MUL2_START, ST_MUL2_WAIT,   // T = U*T
    ST_U2_X3,           // U2=U^2 ; X3 = U2 + T + a2*Z3
    ST_S2,              // S2 = S^2
    ST_MUL3_START, ST_MUL3_WAIT,   // term1 = (Z3+T) * X3
    ST_MUL4_START, ST_MUL4_WAIT,   // term2 = S2 * Z3
    ST_Y3,
    DONE_ST
  } state_t;
  state_t state;

  logic [W-1:0] X1_r, Z1_r;
  logic [W-1:0] S_r, U_r, T_r, Z3_r, U2_r, S2_r, X3_r, term1_r, Y3_r;

  logic         mul_start, mul_busy, mul_done;
  logic [W-1:0] mul_a, mul_b, mul_product;

  gf2m_mult_serial u_mult (
    .clk, .rst_n,
    .start(mul_start), .a_in(mul_a), .b_in(mul_b),
    .busy(mul_busy), .done(mul_done), .product(mul_product)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= IDLE;
      mul_start <= 1'b0;
      done      <= 1'b0;
      X1_r <= '0; Z1_r <= '0;
      S_r <= '0; U_r <= '0; T_r <= '0; Z3_r <= '0;
      U2_r <= '0; S2_r <= '0; X3_r <= '0; term1_r <= '0; Y3_r <= '0;
      X3_out <= '0; Y3_out <= '0; Z3_out <= '0;
    end else begin
      mul_start <= 1'b0;
      done      <= 1'b0;

      unique case (state)
        IDLE: begin
          if (start) begin
            X1_r  <= X1_in;
            Z1_r  <= Z1_in;
            S_r   <= gf_square(X1_in);
            U_r   <= gf_square(X1_in) ^ Y1_in;
            state <= ST_S_U;
          end
        end

        ST_S_U: begin // let S_r/U_r settle before the first multiply
          mul_a     <= X1_r;
          mul_b     <= Z1_r;
          mul_start <= 1'b1;
          state     <= ST_MUL1_START;
        end

        ST_MUL1_START: begin
          if (mul_done) begin
            T_r   <= mul_product;   // T = X1*Z1
            state <= ST_Z3;
          end
        end

        ST_Z3: begin
          Z3_r  <= gf_square(T_r);
          state <= ST_MUL2_START;
        end

        ST_MUL2_START: begin
          mul_a     <= U_r;
          mul_b     <= T_r;
          mul_start <= 1'b1;
          state     <= ST_MUL2_WAIT;
        end

        ST_MUL2_WAIT: begin
          if (mul_done) begin
            T_r   <= mul_product;   // T <- U*T
            state <= ST_U2_X3;
          end
        end

        ST_U2_X3: begin
          U2_r  <= gf_square(U_r);
          X3_r  <= gf_square(U_r) ^ T_r ^ mul_a2(Z3_r);
          state <= ST_S2;
        end

        ST_S2: begin
          S2_r  <= gf_square(S_r);
          state <= ST_MUL3_START;
        end

        ST_MUL3_START: begin
          mul_a     <= Z3_r ^ T_r;
          mul_b     <= X3_r;
          mul_start <= 1'b1;
          state     <= ST_MUL3_WAIT;
        end

        ST_MUL3_WAIT: begin
          if (mul_done) begin
            term1_r <= mul_product; // term1 = (Z3+T)*X3
            state   <= ST_MUL4_START;
          end
        end

        ST_MUL4_START: begin
          mul_a     <= S2_r;
          mul_b     <= Z3_r;
          mul_start <= 1'b1;
          state     <= ST_MUL4_WAIT;
        end

        ST_MUL4_WAIT: begin
          if (mul_done) begin
            Y3_r  <= term1_r ^ mul_product; // Y3 = term1 + S2*Z3
            state <= ST_Y3;
          end
        end

        ST_Y3: begin
          X3_out <= X3_r;
          Y3_out <= Y3_r;
          Z3_out <= Z3_r;
          state  <= DONE_ST;
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
