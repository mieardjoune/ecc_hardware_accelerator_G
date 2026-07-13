# ecc_hardware_accelerator_G

Elliptic Curve Scalar Multiplication Hardware Accelerator over GF(2^233), using Modified
Lopez-Dahab projective coordinates, running on a QMTECH Artix-7 board.
Send a scalar k over UART, get k*G back, computed on the FPGA.

## What's here

- SystemVerilog implementation of GF(2^233) arithmetic (multiply, square,
  Itoh-Tsujii inversion) and Modified Lopez-Dahab point addition,
  doubling, and scalar multiplication (`src/`).
- A UART bridge (`ecc_uart_top`) send 30 bytes for k, get 61 bytes back for k*G,
  at 115200 baud.
- A Python implementation of the same math (`python_model/`), written
  separately from the RTL and used to generate the test vectors it's
  checked against.
- Testbenches for every module (`tb/`), including one that drives a
  real, bit-accurate UART stream into the design and checks the
  response.
- A small Python script (`host/ecc_uart_client.py`) for talking to the
  board over a serial port.


## Repository layout 

> **Note:** This repository structure is meant to be inside qmtech workspace project (Check [this](https://github.com/mieardjoune/qmtech-artix-7-workspace)) and the constraints are for the QMTECH Artix-7 board. Adjust as necessary.
```bash
ecc_hardware_accelerator_G/
  TOP                                   # Top module name: ecc_uart_top
  params.txt                            # Generics for synth_design -generic
  constraints/
    physical.xdc                        # Pin assignments (clock, reset, UART)
  src/
    00_gf2m_pkg.sv)                     # GF(2^233) constants and helper functions
    gf2m_mult_serial.sv                 # Shift-and-add multiplier
    gf2m_inverse.sv                     # Itoh-Tsujii inversion
    ld_point_double.sv                  # Point doubling
    ld_point_add.sv                     # Point addition
    ecc_hardware_accelerator_G.sv       # Scalar multiplier core
    uart_tx.sv/uart_rx.sv  UART
    ecc_uart_top.sv                     # Top module, wires everything to board pins

  tb/                                   # One testbench per module, plus the full
                                        # Protocol test (ecc_uart_top_tb.sv)
  python_model/                         # Reference implementation and its own tests
  host/
    ecc_uart_client.py                  # Talk to hardware over a serial port
  docs/
    MATH.md                             # The math, explained
    HDL_ARCHITECTURE.md                 # Module-by-module walkthrough
    UART_PROTOCOL.md                    # Wire format
    KNOWN_ANSWER_TESTS.md               # Test vectors
```

## Building and simulating

Same flow defined by the workspace:

```bash
make sim PRJ=ecc_hardware_accelerator_G        # RTL simulation (Icarus Verilog)
make build PRJ=ecc_hardware_accelerator_G      # Synthesis + implementation + bitstream
make sim-gate PRJ=ecc_hardware_accelerator_G   # Gate-level timing simulation
make deploy PRJ=ecc_hardware_accelerator_G     # Program the board over JTAG
```

## Testing on real hardware

```bash
   sudo apt update
   sudo apt install python3-serial
   sudo python3 projects/ecc_hardware_accelerator_G/host/ecc_uart_client.py /dev/ttyUSB0 12345 --check
```

   `--check` compares the FPGA's answer against `python_model/`
   automatically. Expected output for k=12345:

   ```
   k = 12345:
     x = 0x171cdbf80d4cf050fafeea2b01039d6ae34aca712ff64ec8037a8496138
     y = 0x13449a47f49a1f7bfbafa5ed0d36958e5f36d3be206adf07262f79bc2e1
   OK: matches python_model
   ```

   You can also open a serial terminal at 115200 8-N-1 and send the 30
   bytes yourself. See `docs/UART_PROTOCOL.md` for the byte layout.

3. Check the clock frequency before trusting the baud rate. This design
   uses `clk_in1_0` directly as the system clock, no PLL. The UART divider
   is computed from `params.txt`'s `CLK_FREQ_HZ=50000000`. That assumes a
   50MHz oscillator on that pin. If your board runs a different
   frequency, update both `constraints/physical.xdc`'s clock period and
   `params.txt`'s `CLK_FREQ_HZ` to match, or the baud rate will be wrong.



## Results
| Metric | Value |
| :--- | :--- |
| Area: Slice LUTs (with UART) | 9,650 (15.22% utilization) Post-Implementation |
| Area: Slice Registers (with UART) | 15,870 (12.52% utilization) Post-Implementation |
| Area: Total Slices (with UART) | 3,896 (24.58% utilization) Post-Implementation |
| Total On-Chip Power | 0.161 W |
| Dynamic Power | 0.064 W |
| Static Power | 0.097 W |
| Target Clock Period | 20.000 ns (50.000 MHz) |
| Worst Negative Slack (WNS) | 4.472 ns (Overall Design) / 7.279 ns (Intra-Clock Setup) |
| Maximum Frequency (f_max) | ~64.40 MHz (Overall WNS) / ~78.61 MHz (Internal logic setup) |
| One Scalar Multiplication Time (Simulation at 50 MHz) | 3.84 milliseconds (192,044 clock cycles) |
| Total Time with UART Overhead (Simulation at 50 MHz) | 13.90 milliseconds (695,109 clock cycles) |

*Note: The hardware area values represent the complete top-level system, which includes both the ECC calculation core and the UART communication logic combined. These numbers are extracted from the final post-implementation routing reports. The simulation times are scaled directly for the target 50 MHz hardware clock from the cycles verified in the waveform data.*
## What this is for

This is meant to be read, not just used. One shared multiplier per
module, driven by a plain state machine, rather than a fast parallel
design. See `docs/HDL_ARCHITECTURE.md` for the reasoning and what you'd
change to make it faster.

It's not production cryptography. It's not constant-time (how long a
scalar multiplication takes depends on the scalar, intentional,
so you can check the cycle counts), it hasn't been audited, and
binary field curves like this one aren't recommended for new
designs anymore. Use an audited library for anything that actually needs
to be secure.

## License

[Apache 2.0](LICENSE)
