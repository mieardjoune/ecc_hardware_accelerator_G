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
// File        : ecc_uart_top_tb.sv
// Project     : qmtech-workspace / ecc_hardware_accelerator_G
// Standard    : IEEE 1800-2012 (SystemVerilog)
// Description : End-to-end, self-checking testbench for ecc_uart_top.
//               Drives RXD_0 with a real UART bit stream encoding a
//               scalar k, waits for TXD_0 to send back the fixed
//               61-byte response, decodes it, and checks it against the
//               known-answer vectors in docs/KNOWN_ANSWER_TESTS.md.
// =============================================================================
//
// GATE_SIM is defined explicitly by scripts/sim_gate.tcl (xvlog -d
// GATE_SIM) when compiling this testbench against the post-synthesis
// netlist. That netlist was synthesized with the real board parameters
// from params.txt (CLK_FREQ_HZ=50000000, BAUD_RATE=115200) already
// resolved, and has no parameters left to override -- so this testbench
// switches its own clock period and expected CLK_FREQ_HZ/BAUD_RATE to
// match, rather than trying to instantiate the netlist with a `#(...)`
// override that no longer exists. Plain RTL simulation (sim-sv) instead
// overrides both to a small, exact ratio (CLKS_PER_BIT = 4) purely to
// keep the UART framing overhead short in simulation -- the ECC core
// itself is untouched either way and still walks the full 233-bit
// scalar, so both paths exercise the real computation, just not at the
// same wall-clock ratio. See README.md for the real hardware settings.

`timescale 1ns/1ps

module ecc_uart_top_tb;
  import gf2m_pkg::*;

`ifdef GATE_SIM
  localparam int      CLK_FREQ_HZ = 50_000_000;
  localparam int      BAUD_RATE   = 115_200;
  localparam realtime CLK_PERIOD  = 20.0; // matches constraints/physical.xdc
`else
  localparam int      CLK_FREQ_HZ = 400_000;
  localparam int      BAUD_RATE   = 100_000; // CLKS_PER_BIT = 4
  localparam realtime CLK_PERIOD  = 10.0;
`endif

  localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
  localparam int NBYTES       = (W + 7) / 8; // 30

  logic clk = 0;
  logic ext_reset_in_0;
  logic TXD_0;
  logic RXD_0;

  int errors = 0;

  always #(CLK_PERIOD/2.0) clk = ~clk;

`ifdef GATE_SIM
  ecc_uart_top uut (
    .clk_in1_0(clk),
    .ext_reset_in_0,
    .TXD_0,
    .RXD_0
  );
`else
  ecc_uart_top #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) uut (
    .clk_in1_0(clk),
    .ext_reset_in_0,
    .TXD_0,
    .RXD_0
  );
`endif

  initial begin
    `ifndef GATE_SIM
    `ifndef SYNTHESIS
      $dumpfile("waveform.vcd");
      $dumpvars(0, ecc_uart_top_tb);
    `endif
    `endif
  end

  // Bit period in real time units, derived the same way the RTL derives
  // CLKS_PER_BIT, so this testbench keeps working if CLK_PERIOD above is
  // ever changed.
  localparam realtime BIT_PERIOD = CLK_PERIOD * CLKS_PER_BIT;

  // Drive RXD_0 with one UART byte (LSB first, 1 start bit, 1 stop bit).
  task automatic uart_send_byte(input logic [7:0] b);
    int i;
    begin
      RXD_0 = 1'b0; #(BIT_PERIOD);           // start bit
      for (i = 0; i < 8; i++) begin
        RXD_0 = b[i];
        #(BIT_PERIOD);
      end
      RXD_0 = 1'b1; #(BIT_PERIOD);           // stop bit
    end
  endtask

  // Receive one UART byte from TXD_0 (blocks until a start bit is seen).
  task automatic uart_recv_byte(output logic [7:0] b);
    int i;
    begin
      wait (TXD_0 == 1'b0);                  // start bit begins
      #(BIT_PERIOD * 1.5);                   // sample middle of bit 0
      for (i = 0; i < 8; i++) begin
        b[i] = TXD_0;
        #(BIT_PERIOD);
      end
      // stop bit: don't bother checking, just let it pass
    end
  endtask

  task automatic send_scalar(input logic [W-1:0] k);
    logic [8*NBYTES-1:0] padded;
    int i;
    begin
      padded = {{(8*NBYTES-W){1'b0}}, k};
      for (i = NBYTES-1; i >= 0; i--) begin
        uart_send_byte(padded[8*i +: 8]);
      end
    end
  endtask

  task automatic recv_response(output logic [7:0] status,
                                output logic [W-1:0] qx,
                                output logic [W-1:0] qy);
    logic [8*NBYTES-1:0] qx_padded, qy_padded;
    logic [7:0] byte_v;
    int i;
    begin
      uart_recv_byte(status);
      qx_padded = '0;
      for (i = NBYTES-1; i >= 0; i--) begin
        uart_recv_byte(byte_v);
        qx_padded[8*i +: 8] = byte_v;
      end
      qy_padded = '0;
      for (i = NBYTES-1; i >= 0; i--) begin
        uart_recv_byte(byte_v);
        qy_padded[8*i +: 8] = byte_v;
      end
      qx = qx_padded[W-1:0];
      qy = qy_padded[W-1:0];
    end
  endtask

  task automatic run_case(input logic [W-1:0] k, input logic [W-1:0] exp_x,
                           input logic [W-1:0] exp_y, input string name);
    logic [7:0]   status;
    logic [W-1:0] qx, qy;
    begin
      send_scalar(k);
      recv_response(status, qx, qy);
      if (status !== 8'h00) begin
        $display("[FAIL] %s: unexpected status byte %h", name, status);
        errors++;
      end else if (qx !== exp_x || qy !== exp_y) begin
        $display("[FAIL] %s: got (%h, %h) expected (%h, %h)",
                  name, qx, qy, exp_x, exp_y);
        errors++;
      end else begin
        $display("[PASS] %s: (%h, %h)", name, qx, qy);
      end
    end
  endtask

  task automatic run_infinity_case(input logic [W-1:0] k, input string name);
    logic [7:0]   status;
    logic [W-1:0] qx, qy;
    begin
      send_scalar(k);
      recv_response(status, qx, qy);
      if (status !== 8'h01) begin
        $display("[FAIL] %s: expected status 01 (infinity), got %h", name, status);
        errors++;
      end else if (qx !== '0 || qy !== '0) begin
        $display("[FAIL] %s: expected zeroed Qx/Qy alongside infinity status", name);
        errors++;
      end else begin
        $display("[PASS] %s: status=01, Qx=Qy=0 as documented", name);
      end
    end
  endtask

  initial begin
    ext_reset_in_0 = 1'b1;
    RXD_0 = 1'b1; // idle high
    repeat (5) @(posedge clk);
    ext_reset_in_0 = 1'b0;
    repeat (5) @(posedge clk);

    run_case(
      233'd5,
      233'h194ed0ca60c85e59e7c4b69f30c6304a9f485f45032b871c4a23ffec8c1,
      233'h0a52f9459c2fab39c214061e272e1e115e1e01a98e4f09cd5a85d2698c6,
      "k=5 over real UART framing"
    );

    run_case(
      233'd12345,
      233'h171cdbf80d4cf050fafeea2b01039d6ae34aca712ff64ec8037a8496138,
      233'h13449a47f49a1f7bfbafa5ed0d36958e5f36d3be206adf07262f79bc2e1,
      "k=12345 over real UART framing (back-to-back, no reset)"
    );

    run_infinity_case(233'd0, "k=0 -> point at infinity (back-to-back, no reset)");

    if (errors == 0)
      $display("\nPASS: ecc_uart_top_tb - all scalars round-tripped correctly over UART.");
    else begin
      $display("\nFAIL: ecc_uart_top_tb - %0d case(s) failed.", errors);
      $finish(1);
    end

    $finish;
  end

  // Safety net so a protocol bug hangs the simulation instead of running
  // forever.
  initial begin
    #200_000_000; // 200 ms of simulated time
    $display("FAIL: ecc_uart_top_tb - watchdog timeout, design never completed.");
    $finish(1);
  end

endmodule
