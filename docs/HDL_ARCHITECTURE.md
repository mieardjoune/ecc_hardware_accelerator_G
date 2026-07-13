# HDL architecture

What each module in `src/` does, how they connect, and why it's built the
way it is. Read `MATH.md` first for the equations themselves.

## Design approach

Every module here uses one shared multiplier, called one operation at a
time, driven by a plain state machine that follows the equations
directly. This is slower than a design that runs several multiplies in
parallel, but it's easy to verify: each module is checked on its own
against the Python model, including a full 233-bit scalar multiplication
checked against `(n-1)*G == -G`. If you want something faster, this is a
correct starting point to build from.

## Module list

| Module | Purpose | Latency |
|---|---|---|
| `00_gf2m_pkg.sv` | Constants and helper functions (`gf_square`, `xtimes`, `mul_a2`) | - |
| `gf2m_mult_serial.sv` | Shift-and-add multiplier | 233 cycles |
| `gf2m_inverse.sv` | Itoh-Tsujii inversion | ~11x233 cycles plus squarings |
| `ld_point_double.sv` | Point doubling | 4 multiplies, ~4x233 cycles plus overhead |
| `ld_point_add.sv` | Point addition, requires P.Z=1 | 8 multiplies, ~8x233 cycles plus overhead |
| `ecc_hardware_accelerator_G.sv` | Scalar multiplier core | one point-double and point-add per bit of k, plus one final inversion |
| `uart_tx.sv` / `uart_rx.sv` | 8-N-1 UART | 1 bit period per bit |
| `ecc_uart_top.sv` | Top module, wraps the core in the UART protocol (see `UART_PROTOCOL.md`) | one scalar multiplication plus UART framing |

`00_gf2m_pkg.sv` has a numeric prefix so that a plain alphabetical file
glob (`src/*.sv`, which is what the Makefile uses) compiles the package
before anything that imports it. Icarus Verilog compiles files in command
line order and doesn't reorder based on dependencies.

## gf2m_mult_serial

Right-to-left shift-and-add multiplication: one bit of the multiplicand
per clock, the other operand doubled and reduced mod f(x) each cycle. 233
cycles from start to done. Every module that needs a multiply has its own
copy of this rather than sharing one instance across the design, which
costs more area but keeps the wiring simple.

Squaring doesn't go through the multiplier. `gf2m_pkg::gf_square` is
combinational (squaring is linear in characteristic 2, so it's just a bit
spread and a reduction), so it costs no clock cycles.

## gf2m_inverse

Computes a^(2^232 - 1) using the standard double/increment recurrence on
the exponent, then squares once more to get a^(2^233 - 2) = a^-1. The bit
pattern of 232 is fixed at compile time, so this is a small fixed
sequence of steps rather than something computed at runtime.

Used in one place: the final projective-to-affine conversion in
`ecc_hardware_accelerator_G` (x = X * Z^-1, y = Y * Z^-2).

## ld_point_double / ld_point_add

Direct hardware for the equations in `MATH.md`, each run by a small state
machine around one multiplier. 4 multiplies for doubling, 8 for addition.
Squarings are free. Additions are XORs, folded into whichever adjacent
cycle needs them.

`ld_point_add` has no Z1 input port. The point going into the "Z=1" slot
of the addition formula is only ever the module's X1/Y1 inputs, so there
is no way to wire this module up wrong on that front. This matters
because of the Z=1 mistake described in `MATH.md`; making it structurally
impossible is more reliable than a runtime check.

`ld_point_add` doesn't handle Z2=0 (point at infinity) on its own.
Feeding it that doesn't produce a useful answer. `ecc_hardware_accelerator_G` checks
for this case itself before calling it.

## ecc_hardware_accelerator_G

Left-to-right double-and-add:

```
Q <- point at infinity
for each bit of k, most significant first:
    Q <- 2*Q
    if bit == 1:
        Q <- P + Q
(x, y) <- (X/Z, Y/Z^2)
```

Two cases are handled directly in this state machine, since the point
arithmetic modules don't know about the point at infinity themselves:
if Q is still infinity when a 1 bit comes up, the accumulator is loaded
with P directly instead of calling the adder. And k=0 (or an accumulator
that somehow ends at Z=0) is reported as infinity rather than trying to
invert zero.

`k_len` sets how many bits of k are actually used, so a short scalar
doesn't spend cycles walking through leading zeros. `ecc_uart_top` always
passes 233 regardless of the actual value, to keep the wire protocol a
fixed length.

## ecc_uart_top

The module named in `TOP`, and the only one with real pin constraints.
Wraps `ecc_hardware_accelerator_G` with a reset synchronizer for `ext_reset_in_0`,
one `uart_tx` and one `uart_rx`, and a small state machine that collects
30 bytes for k, runs the multiplication against the fixed base point G,
and sends 61 bytes back.

See `UART_PROTOCOL.md` and `host/ecc_uart_client.py` for the protocol and
a working client.

## Handshakes

Every module uses the same three signals: `start` (pulse one cycle to
begin), `busy` (high while running), `done` (pulse one cycle when the
output is valid). Inputs need to stay stable from `start` until `busy`
goes low. This is consistent across every level, multiplier, inverter,
point ops, top-level multiplier, which is what makes it possible to test
each one alone and then put them together with confidence.

