# Known-answer test vectors

These vectors come from `python_model/` and are checked against the RTL
in `src/` by the testbenches in `tb/`. `tb/ecc_uart_top_tb.sv` (run via
`make sim PRJ=ecc_hardware_accelerator_G`) checks the full path end to end; see
README.md for running individual testbenches.

## Field arithmetic

Field: GF(2^233), reduction polynomial f(x) = x^233 + x^74 + 1.

```
X = 0x17232ba853a7e731af129f22ff4149563a419c26bf50a4c9d6eefad6125
Y = 0x1db537dece819b7f70f555a67c427a8cd9bf18aeb9b56e0c11056fae6a3
```

| Operation | Result (hex) | Checked by |
|---|---|---|
| X * Y | 02db9c59a4bbf539e65d0174b12a0c30657655eeacb017a3d4466d2392e | tb_gf2m_mult_serial.sv |
| X^2 | 113bcafec38a1e9f284bec901039e7f0d4bc3b7a1ebd2526abed8419d34 | tb_gf2m_mult_serial.sv, tb_gf2m_square.sv |
| Y^2 | 068f05b49e5578168c45662867bf7802be523e250d9f60f5af90d421ef3 | tb_gf2m_square.sv |
| Y^-1 | 036f0932fbd15fbd39fa1dc9d1462fcb362fbb6d6d716cdf5cf5ef9fae3 | tb_gf2m_inverse.sv |
| X / Y | 05f5c5f3c298f430d4b4c97ff524f588c125d2b03849433100707eda013 | Python only, equals X * Y^-1 |

## Curve: sect233r1 / NIST B-233

```
a  = 1
b  = 0x0066647ede6c332c7f8c0923bb58213b333b20e9ce4281fe115f7d8f90ad
Gx = 0x00fac9dfcbac8313bb2139f1bb755fef65bc391f8b36f8f8eb7371fd558b
Gy = 0x01006a08a41903350678e58528bebf8a0beff867a7ca36716f7e01f81052
n  = 0x01000000000000000000000000000013e974e72f8a6922031d2603cfe0d7
h  = 2
```

## Point doubling / addition, raw projective coordinates

Checked by tb_ld_point_double.sv and tb_ld_point_add.sv.

| Operation | X | Y | Z |
|---|---|---|---|
| 2*G | 017879e3975bc39ca44a3790beacc68d0aabf82f07d8e81f53b364e69b7 | 0c82bd1c103aaccb0bb3fdd1ac18b451b874b7f1f9060bd58c623e6f248 | 0df363367f225632bf562e6f8871c6d98b537780dfad1f3b68accc9afab |
| G + 2G (= 3*G) | 147c656507c1714a8a2c5c5f0d22c9cf90da91049f28428c5438102ad6f | 1e3f0c03b8d98bbd3a4645db25c3162754401c3ff63c71f0d4d4e6d009a | 0e7ad1111868ba5b043e487c976974ad4686aaa69eed525b910a8a64154 |

## Scalar multiplication, final affine coordinates

Checked by tb_ecc_hardware_accelerator_G.sv and tb_ecc_hardware_accelerator_G_full_order.sv.

| k | x | y |
|---|---|---|
| 2 | 0845fd61638bac7d9e109a67a1f7047dc0fd9a5488a8468364bdc592aad | 01b1420774abba2587c83900984765a8a85d776325fc39cc7823d734660 |
| 3 | 080f50a330911bd753a76364595b9f0158c4d02a85cc0e3fb6ea0aef9ff | 17a49033f12eb52675e98e6432cc27104bd5c42bcbe3daf76901c9b8743 |
| 5 | 194ed0ca60c85e59e7c4b69f30c6304a9f485f45032b871c4a23ffec8c1 | 0a52f9459c2fab39c214061e272e1e115e1e01a98e4f09cd5a85d2698c6 |
| 12345 | 171cdbf80d4cf050fafeea2b01039d6ae34aca712ff64ec8037a8496138 | 13449a47f49a1f7bfbafa5ed0d36958e5f36d3be206adf07262f79bc2e1 |
| n-1 | 0fac9dfcbac8313bb2139f1bb755fef65bc391f8b36f8f8eb7371fd558b (equals Gx) | 1faa3d76fb58026bd59dc7493cbe0656e53c1782cfcce89840d700545d9 |
| 0 | point at infinity | point at infinity |
| n | point at infinity | point at infinity |

The n-1 row is the strongest test here: it walks the full 233-bit scalar
and checks (n-1)*G == -G. On this curve -P = (x, x+y), so the x
coordinate alone should equal Gx, which is a quick check to run first if
something doesn't match.

tb/ecc_uart_top_tb.sv checks the k=5, k=12345, and k=0 rows again, this
time through a simulated UART link rather than connecting straight to
ecc_hardware_accelerator_G's ports. See UART_PROTOCOL.md.
