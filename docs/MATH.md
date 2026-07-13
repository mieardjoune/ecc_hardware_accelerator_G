# Notes on the math

This project implements elliptic curve scalar multiplication over
GF(2^233) using Modified Lopez-Dahab coordinates, in SystemVerilog
(`src/`). There is also a Python version (`python_model/`) written
separately from the RTL, used only to work out the equations first and to
generate test vectors to check the hardware against. Two different
implementations of the same math is a cheap way to catch mistakes that a
single implementation, however carefully checked, would miss.

This note explains the math, and two mistakes that showed up while
building it that are worth knowing about if you're learning this topic.

## The field: GF(2^233)

Elements are binary polynomials of degree less than 233, stored in
polynomial basis: bit `i` of an integer is the coefficient of `x^i`.
Reduction uses

```
f(x) = x^233 + x^74 + 1
```

This is the reduction polynomial specified by the NIST/SECG standard for
curve `sect233r1` (also called NIST B-233).

Addition is XOR. This is a characteristic-2 field, so `a + a = 0` for
every element, and addition and subtraction are the same operation.

Multiplication (`gf2m.gf_mul`) is the standard right-to-left
shift-and-add algorithm: walk the bits of one operand, doubling the other
operand (and reducing modulo `f(x)`) each step, adding it in whenever the
current bit is 1.

Squaring (`gf2m.gf_square`) is cheaper than a general multiply. In
characteristic 2, squaring is linear (this is the Frobenius map), so
`a(x)^2` can be computed by spreading the bits of `a` two positions apart
and then reducing, no multiplication needed. This is why the hardware
design uses a combinational squarer instead of running squares through
the multiplier.

Inversion has two independent implementations, checked against each
other in `tests/test_gf2m.py`:

- `gf2m.gf_inv_fermat`: the obvious one, `a^(2^233-2)` by
  square-and-multiply. About 230 multiplications, easy to verify by
  reading it, slow.
- `gf2m.gf_inv_itoh_tsujii`: the Itoh-Tsujii method, about 11
  multiplications plus some squarings, built from the bits of `232`.
  This is the one actually used everywhere else (`gf2m.gf_inv`).

## Modified Lopez-Dahab coordinates

Plain affine arithmetic needs one field inversion per point addition,
which is expensive in hardware. Projective coordinates trade that
inversion for a few extra multiplications, and only pay for one inversion
at the very end of a scalar multiplication.

A projective point `(X : Y : Z)`, with `Z != 0`, represents the affine
point

```
x = X / Z
y = Y / Z^2
```

The asymmetric scaling here, `Z` for `x` and `Z^2` for `y`, is what makes
this "Lopez-Dahab" coordinates rather than the more common Jacobian form.

The "modified" version of these coordinates (from Tanja Lange's note on
Lopez-Dahab coordinates) speeds up point addition further when one of the
two points being added has `Z = 1`. That's the normal situation when one
of the points is a fixed point that never gets updated, like a base point
you keep multiplying, so it's worth special-casing. Here are the
equations used in this project:

```
Doubling: P = (X1 : Y1 : Z1), Z1 can be anything
    S  = X1^2
    U  = S + Y1
    T  = X1*Z1
    Z3 = T^2
    T  = U*T
    X3 = U^2 + T + a2*Z3
    Y3 = (Z3 + T)*X3 + S^2*Z3

Addition: P = (X1 : Y1 : 1), Q = (X2 : Y2 : Z2), P.Z must be 1
    U  = Z2^2*Y1 + Y2
    S  = Z2*X1 + X2
    T  = Z2*S
    Z3 = T^2
    V  = Z3*X1
    C  = X1 + Y1
    X3 = U^2 + T*(U + S^2 + a2*T)
    Y3 = (V + X3)*(T*U + Z3) + Z3^2*C
```

`a2` is the field element with `a2^2 = a`. For the curve used here `a =
1`, so `a2 = 1` too.

Both formulas are implemented directly in `python_model/ecc_gf2m/lopez_dahab.py`
(`ld_double`, `ld_add`) and checked against a plain textbook affine
implementation (`python_model/ecc_gf2m/affine_ref.py`) using random points,
and again in the SystemVerilog (`src/ld_point_double.sv`,
`src/ld_point_add.sv`) against the Python output.

## Two mistakes worth knowing about

An earlier attempt at this same design, on the same curve and the same
formulas, existed only as a university project write-up (not published,
not something you can look up). Working through the math to reimplement
it properly and test it turned up two real mistakes in that earlier
attempt, described below because they're useful things to watch for if
you're implementing this yourself.

### Converting from projective back to affine

Going from `(X : Y : Z)` back to affine coordinates needs `y = Y / Z^2`,
as shown above. The earlier attempt skipped that division, reasoning that
`1/Z^2 = 1` so `y` could just be read off directly as `Y`.

That's only true when `Z` happens to equal 1. After an actual scalar
multiplication, `Z` is essentially never 1, so this shortcut gives the
wrong `y` coordinate almost every time.

This project does the division correctly
(`lopez_dahab.to_affine`), and keeps the broken version around too,
clearly labeled, as `lopez_dahab.to_affine_naive`, so the mistake
can be reproduced and compared directly
(`tests/test_lopez_dahab.py::test_naive_y_conversion_is_wrong_in_general`).

### Which point has to stay at Z=1

The addition formula above only works if one specific input, `P`, has
`Z = 1`, and stays that way. The earlier scalar-multiplication algorithm
started `P` at `Z = 1` correctly, but then doubled that same point every
loop iteration while also feeding it into the addition step as if it
still had `Z = 1`. After the very first doubling it doesn't anymore, so
the addition formula is being used outside the conditions it needs.

The fix is to swap which point plays which role: keep `P` fixed forever
at `Z = 1`, and instead double the accumulator (which is allowed to have
any `Z`), adding the fixed `P` in whenever the current bit of the scalar
is 1. Written out:

```
Q <- point at infinity
for each bit of k, most significant first:
    Q <- 2*Q            (Q can have any Z)
    if bit == 1:
        Q <- Q + P       (P fixed at Z=1, matches what the formula needs)
return Q
```

This is what `lopez_dahab.scalar_mult` does. The original, broken version
is kept as `lopez_dahab.scalar_mult_naive` for comparison: it raises an
error the moment the Z=1 assumption breaks, rather than quietly
returning a wrong answer
(`tests/test_lopez_dahab.py::test_naive_scalar_mult_breaks_as_documented`).
This is a plausible reason the earlier attempt at this design produced no
usable output when tested on an FPGA.

## What this project builds, and what it doesn't

The earlier hardware attempt's point addition, point doubling, and field
multiplication/division circuits existed only as Quartus schematic
diagrams, not as text, so there's nothing to port directly even if it had
been fully correct. What's in `src/` here is a fresh SystemVerilog
implementation of the corrected math above, described in
`docs/HDL_ARCHITECTURE.md`, simulated end to end against the vectors in
`docs/KNOWN_ANSWER_TESTS.md`. That includes a full 233-bit scalar
multiplication that checks out against `(n-1)*G == -G`, and a full round
trip through the UART bridge (`ecc_uart_top`) on top of that.
