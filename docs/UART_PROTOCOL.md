# UART wire protocol

`ecc_uart_top` exposes the scalar multiplier over a plain 8-N-1,
115200-baud UART link, so the design can be tested from a laptop with a
USB-serial adapter and a terminal, or the script in `host/`.

The base point is fixed to the generator G of curve sect233r1. You send a
scalar k and get back k*G. There's no way to send a custom point over
this link, only a custom scalar.

## Framing

8-N-1: 1 start bit, 8 data bits (LSB first), 1 stop bit, no parity,
115200 baud. This is the default for basically every terminal program
and serial library.

## Host to FPGA: send a scalar

Send exactly 30 bytes, most significant byte first: a 240-bit big-endian
number whose low 233 bits are k. The top 7 bits are padding and must be
sent as zero.

```
byte 0  (MSB)
byte 1
  ...        k, big-endian, top 7 bits of byte 0 are padding (zero)
byte 29 (LSB)
```

## FPGA to host: the result

Once the computation finishes, the FPGA sends back exactly 61 bytes,
every time:

| Bytes | Meaning |
|---|---|
| 0 | status: 0x00 = finite point follows, 0x01 = point at infinity |
| 1-30 | Qx, same encoding as the input |
| 31-60 | Qy, same encoding |

If status is 0x01 (only happens when k is 0 or a multiple of the curve
order), bytes 1-60 are still sent, all zero. The response is always the
same length, so a host script never has to branch on how many bytes to
read.

After sending the response, the FPGA goes straight back to waiting for
the next scalar. No reset needed between runs, see
`tb/ecc_uart_top_tb.sv` for an example that runs three scalars back to
back.

## Example

Sending k = 5 (29 zero bytes then 0x05) should produce:

```
Qx = 0x194ed0ca60c85e59e7c4b69f30c6304a9f485f45032b871c4a23ffec8c1
Qy = 0x0a52f9459c2fab39c214061e272e1e115e1e01a98e4f09cd5a85d2698c6
```

## Testing it

```bash
pip install pyserial
python3 host/ecc_uart_client.py /dev/ttyUSB0 5
```

Add `--check` to compare the FPGA's answer against `python_model/`
automatically instead of just printing it.

## Extending this

A few things you could add if you want to build on this:

Custom base point: extend the protocol to accept Px, Py before k, and
wire them to ecc_hardware_accelerator_G's Px_in/Py_in ports instead of the hardcoded
values.

Variable-length scalars: send a 1-byte length prefix and wire it to
k_len instead of hardcoding it to 233, so short scalars finish faster.

Batching: if you want a table of 1*G, 2*G, 3*G and so on, you'd need to
change both the protocol and the state machine, since right now it
processes one request at a time and won't accept a new scalar until it's
done responding to the last one.
