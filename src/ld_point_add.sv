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
// File        : ld_point_add.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Modified Lopez-Dahab point addition. P + Q = (X3:Y3:Z3),
//               P must have Z=1, enforced by giving this module no Z1
//               port at all. See docs/MATH.md.
// =============================================================================
`timescale 1ns / 1ps
//
//   U  = Z2^2*Y1 + Y2
//   S  = Z2*X1 + X2
//   T  = Z2*S
//   Z3 = T^2
//   V  = Z3*X1
//   C  = X1 + Y1
//   X3 = U^2 + T*(U + S^2 + a2*T)
//   Y3 = (V + X3)*(T*U + Z3) + Z3^2*C

module ld_point_add
  import gf2m_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,
  input  logic          start,
  input  logic [W-1:0]  X1_in,   // P, Z1 == 1 (no Z1 port)
  input  logic [W-1:0]  Y1_in,
  input  logic [W-1:0]  X2_in,   // Q, general Z2
  input  logic [W-1:0]  Y2_in,
  input  logic [W-1:0]  Z2_in,
  output logic          busy,
  output logic          done,
  output logic [W-1:0]  X3_out,
  output logic [W-1:0]  Y3_out,
  output logic [W-1:0]  Z3_out
);

  typedef enum logic [4:0] {
    IDLE,
    ST_MUL1_START,
    ST_MUL2_START,
    ST_MUL3_START, ST_MUL3_WAIT,
    ST_Z3,
    ST_MUL4_START, ST_MUL4_WAIT,
    ST_MUL5_START, ST_MUL5_WAIT,
    ST_MUL6_START,
    ST_X3,
    ST_MUL7_START, ST_MUL7_WAIT,
    ST_MUL8_START,
    ST_Y3,
    DONE_ST
  } state_t;
  state_t state;

  logic [W-1:0] X1_r, Y1_r, X2_r, Y2_r, Z2_r;
  logic [W-1:0] U_r, S_r, T_r, Z3_r, V_r, C_r, X3_r, TU_r, Y3_r;

  logic         mul_start, mul_busy, mul_done;
  logic [W-1:0] mul_a, mul_b, mul_product;

  gf2m_mult_serial u_mult (
    .clk, .rst_n,
    .start(mul_start), .a_in(mul_a), .b_in(mul_b),
    .busy(mul_busy), .done(mul_done), .product(mul_product)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      mul_start <= 1'b0;
      done <= 1'b0;
      {X1_r,Y1_r,X2_r,Y2_r,Z2_r} <= '0;
      {U_r,S_r,T_r,Z3_r,V_r,C_r,X3_r,TU_r,Y3_r} <= '0;
      X3_out <= '0; Y3_out <= '0; Z3_out <= '0;
    end else begin
      mul_start <= 1'b0;
      done      <= 1'b0;

      unique case (state)
        IDLE: begin
          if (start) begin
            X1_r <= X1_in; Y1_r <= Y1_in;
            X2_r <= X2_in; Y2_r <= Y2_in; Z2_r <= Z2_in;
            C_r  <= X1_in ^ Y1_in;         // C = X1 + Y1
            mul_a <= gf_square(Z2_in);
            mul_b <= Y1_in;
            mul_start <= 1'b1;
            state <= ST_MUL1_START;
          end
        end

        ST_MUL1_START: begin
          if (mul_done) begin
            U_r   <= mul_product ^ Y2_r;   // U = Z2^2*Y1 + Y2
            mul_a <= Z2_r;
            mul_b <= X1_r;
            mul_start <= 1'b1;
            state <= ST_MUL2_START;
          end
        end

        ST_MUL2_START: begin
          if (mul_done) begin
            S_r   <= mul_product ^ X2_r;   // S = Z2*X1 + X2
            mul_a <= Z2_r;
            state <= ST_MUL3_START;        // mul_b assigned below once S ready
          end
        end

        // one cycle to let S_r settle before using it as an operand
        ST_MUL3_START: begin
          mul_b     <= S_r;
          mul_start <= 1'b1;
          state     <= ST_MUL3_WAIT;
        end

        ST_MUL3_WAIT: begin
          if (mul_done) begin
            T_r   <= mul_product;          // T = Z2*S
            state <= ST_Z3;
          end
        end

        ST_Z3: begin
          Z3_r  <= gf_square(T_r);
          state <= ST_MUL4_START;
        end

        ST_MUL4_START: begin
          mul_a     <= Z3_r;
          mul_b     <= X1_r;
          mul_start <= 1'b1;
          state     <= ST_MUL4_WAIT;
        end

        ST_MUL4_WAIT: begin
          if (mul_done) begin
            V_r   <= mul_product;          // V = Z3*X1
            state <= ST_MUL5_START;
          end
        end

        ST_MUL5_START: begin
          mul_a     <= T_r;
          mul_b     <= U_r ^ gf_square(S_r) ^ mul_a2(T_r);
          mul_start <= 1'b1;
          state     <= ST_MUL5_WAIT;
        end

        ST_MUL5_WAIT: begin
          if (mul_done) begin
            X3_r  <= gf_square(U_r) ^ mul_product; // X3 = U^2 + T*(...)
            mul_a <= T_r;
            mul_b <= U_r;
            mul_start <= 1'b1;
            state <= ST_MUL6_START;
          end
        end

        ST_MUL6_START: begin
          if (mul_done) begin
            TU_r  <= mul_product;          // T*U
            state <= ST_X3;
          end
        end

        ST_X3: begin // X3_r already set above, settle before mul7 uses it
          state <= ST_MUL7_START;
        end

        ST_MUL7_START: begin
          mul_a     <= V_r ^ X3_r;
          mul_b     <= TU_r ^ Z3_r;
          mul_start <= 1'b1;
          state     <= ST_MUL7_WAIT;
        end

        ST_MUL7_WAIT: begin
          if (mul_done) begin
            Y3_r  <= mul_product;          // Y3 partial = (V+X3)*(TU+Z3)
            mul_a <= gf_square(Z3_r);
            mul_b <= C_r;
            mul_start <= 1'b1;
            state <= ST_MUL8_START;
          end
        end

        ST_MUL8_START: begin
          if (mul_done) begin
            Y3_r  <= Y3_r ^ mul_product;   // Y3 = Y3_partial + Z3^2*C
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
