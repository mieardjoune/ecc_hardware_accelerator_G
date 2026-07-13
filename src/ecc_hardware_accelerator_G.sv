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
// File        : ecc_hardware_accelerator_G.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : Scalar multiplier core: k*P over GF(2^233) / sect233r1
//               using Modified Lopez-Dahab coordinates. See docs/MATH.md.
// =============================================================================
`timescale 1ns / 1ps
//
//     Q <- point at infinity
//     for each bit of k, MSB to LSB:
//         Q <- 2*Q
//         if bit == 1:
//             Q <- P + Q
//     (x, y) <- (Qx/Qz, Qy/Qz^2)
//
// P is wired into ld_point_add's Z1=1 operand and never updated, so that
// precondition holds for the whole computation. k_len sets how many low
// bits of k_in are used; the module scans from bit (k_len-1) down to 0.

module ecc_hardware_accelerator_G
  import gf2m_pkg::*;
#(
  parameter int KBITS = W   // scalar width; caller sets k_len <= KBITS
)(
  input  logic              clk,
  input  logic              rst_n,
  input  logic              start,
  input  logic [KBITS-1:0]  k_in,
  input  logic [$clog2(KBITS+1)-1:0] k_len,   // number of significant bits of k_in
  input  logic [W-1:0]      Px_in,
  input  logic [W-1:0]      Py_in,
  output logic              busy,
  output logic              done,
  output logic              result_is_infinity,
  output logic [W-1:0]      Qx_out,
  output logic [W-1:0]      Qy_out
);

  typedef enum logic [3:0] {
    IDLE,
    BIT_LOOP_DBL_START, BIT_LOOP_DBL_WAIT,
    BIT_LOOP_ADD_START, BIT_LOOP_ADD_WAIT,
    BIT_LOOP_NEXT,
    CONVERT_ZINV_START, CONVERT_ZINV_WAIT,
    CONVERT_ZINV2,
    CONVERT_MULX_START,
    CONVERT_MULY_START,
    DONE_ST
  } state_t;
  state_t state;

  logic [W-1:0] Px_r, Py_r;
  logic [KBITS-1:0] k_r;
  logic [$clog2(KBITS+1)-1:0] bit_idx;

  // Accumulator Q in LD projective coordinates; Z_acc == 0 encodes infinity.
  logic [W-1:0] Xacc, Yacc, Zacc;

  // Sub-module handshakes
  logic          pd_start, pd_busy, pd_done;
  logic [W-1:0]  pd_X3, pd_Y3, pd_Z3;

  logic          pa_start, pa_busy, pa_done;
  logic [W-1:0]  pa_X3, pa_Y3, pa_Z3;

  logic          inv_start, inv_busy, inv_done;
  logic [W-1:0]  inv_out;

  logic          mul_start, mul_busy, mul_done;
  logic [W-1:0]  mul_a, mul_b, mul_product;

  logic [W-1:0]  zinv_r, zinv2_r;

  ld_point_double u_pd (
    .clk, .rst_n,
    .start(pd_start),
    .X1_in(Xacc), .Y1_in(Yacc), .Z1_in(Zacc),
    .busy(pd_busy), .done(pd_done),
    .X3_out(pd_X3), .Y3_out(pd_Y3), .Z3_out(pd_Z3)
  );

  ld_point_add u_pa (
    .clk, .rst_n,
    .start(pa_start),
    .X1_in(Px_r), .Y1_in(Py_r),      // P, Z1 == 1 structurally
    .X2_in(Xacc), .Y2_in(Yacc), .Z2_in(Zacc), // Q, general Z
    .busy(pa_busy), .done(pa_done),
    .X3_out(pa_X3), .Y3_out(pa_Y3), .Z3_out(pa_Z3)
  );

  gf2m_inverse u_inv (
    .clk, .rst_n,
    .start(inv_start),
    .a_in(Zacc),
    .busy(inv_busy), .done(inv_done),
    .inv_out(inv_out)
  );

  gf2m_mult_serial u_mult (
    .clk, .rst_n,
    .start(mul_start),
    .a_in(mul_a), .b_in(mul_b),
    .busy(mul_busy), .done(mul_done),
    .product(mul_product)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      pd_start <= 1'b0; pa_start <= 1'b0; inv_start <= 1'b0; mul_start <= 1'b0;
      done <= 1'b0;
      result_is_infinity <= 1'b0;
      Px_r <= '0; Py_r <= '0; k_r <= '0; bit_idx <= '0;
      Xacc <= '0; Yacc <= '0; Zacc <= '0;
      zinv_r <= '0; zinv2_r <= '0;
      Qx_out <= '0; Qy_out <= '0;
    end else begin
      pd_start  <= 1'b0;
      pa_start  <= 1'b0;
      inv_start <= 1'b0;
      mul_start <= 1'b0;
      done      <= 1'b0;

      unique case (state)
        IDLE: begin
          if (start) begin
            Px_r <= Px_in;
            Py_r <= Py_in;
            k_r  <= k_in;
            if (k_len == 0) begin
              result_is_infinity <= 1'b1;
              Qx_out <= '0;
              Qy_out <= '0;
              state  <= DONE_ST;
            end else begin
              bit_idx <= k_len - 1'b1;
              Xacc <= '0; Yacc <= '0; Zacc <= '0; // Q <- infinity
              result_is_infinity <= 1'b0;
              state <= BIT_LOOP_DBL_START;
            end
          end
        end

        // ---- Q <- 2*Q --------------------------------------------------
        BIT_LOOP_DBL_START: begin
          pd_start <= 1'b1;
          state    <= BIT_LOOP_DBL_WAIT;
        end

        BIT_LOOP_DBL_WAIT: begin
          if (pd_done) begin
            Xacc  <= pd_X3;
            Yacc  <= pd_Y3;
            Zacc  <= pd_Z3;
            if (k_r[bit_idx]) begin
              if (pd_Z3 == '0) begin
                // Q is still infinity: O + P = P. ld_point_add doesn't
                // handle Z2=0 itself, so this is handled here instead.
                Xacc  <= Px_r;
                Yacc  <= Py_r;
                Zacc  <= 1;
                state <= BIT_LOOP_NEXT;
              end else begin
                state <= BIT_LOOP_ADD_START;
              end
            end else begin
              state <= BIT_LOOP_NEXT;
            end
          end
        end

        // ---- Q <- P + Q (only when the current bit is 1) ---------------
        BIT_LOOP_ADD_START: begin
          pa_start <= 1'b1;
          state    <= BIT_LOOP_ADD_WAIT;
        end

        BIT_LOOP_ADD_WAIT: begin
          if (pa_done) begin
            Xacc  <= pa_X3;
            Yacc  <= pa_Y3;
            Zacc  <= pa_Z3;
            state <= BIT_LOOP_NEXT;
          end
        end

        BIT_LOOP_NEXT: begin
          if (bit_idx == 0) begin
            state <= CONVERT_ZINV_START;
          end else begin
            bit_idx <= bit_idx - 1'b1;
            state   <= BIT_LOOP_DBL_START;
          end
        end

        // ---- Final conversion: (x,y) = (X/Z, Y/Z^2) ---------------------
        CONVERT_ZINV_START: begin
          if (Zacc == '0) begin
            result_is_infinity <= 1'b1;
            state <= DONE_ST;
          end else begin
            inv_start <= 1'b1;
            state     <= CONVERT_ZINV_WAIT;
          end
        end

        CONVERT_ZINV_WAIT: begin
          if (inv_done) begin
            zinv_r <= inv_out;
            state  <= CONVERT_ZINV2;
          end
        end

        CONVERT_ZINV2: begin
          zinv2_r   <= gf_square(zinv_r);
          mul_a     <= Xacc;
          mul_b     <= zinv_r;
          mul_start <= 1'b1;
          state     <= CONVERT_MULX_START;
        end

        CONVERT_MULX_START: begin
          if (mul_done) begin
            Qx_out <= mul_product;   // x = X * Z^-1
            mul_a  <= Yacc;
            mul_b  <= zinv2_r;
            mul_start <= 1'b1;
            state  <= CONVERT_MULY_START;
          end
        end

        CONVERT_MULY_START: begin
          if (mul_done) begin
            Qy_out <= mul_product;   // y = Y * Z^-2
            state  <= DONE_ST;
          end
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
