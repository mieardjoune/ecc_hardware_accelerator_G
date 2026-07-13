# Copyright 2026 M. I. E. ARDJOUNE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
"""
lopez_dahab.py
--------------
Modified Lopez-Dahab projective point arithmetic over GF(2^m), from
T. Lange, "A note on Lopez-Dahab coordinates", Cryptology ePrint Archive
2004/155.

A projective point (X : Y : Z), Z != 0, represents the affine point

    x = X / Z ,   y = Y / Z^2

Point addition below assumes the second operand carries an arbitrary Z
and the first operand has Z = 1 permanently (this is what "modified"
buys you: 4 fewer multiplications). Point doubling makes no such
assumption.

  Addition:  P = (X1 : Y1 : 1), Q = (X2 : Y2 : Z2), P != Q
      U = Z2^2*Y1 + Y2
      S = Z2*X1 + X2
      T = Z2*S
      Z3 = T^2
      V = Z3*X1
      C = X1 + Y1
      X3 = U^2 + T*(U + S^2 + a2*T)
      Y3 = (V + X3)*(T*U + Z3) + Z3^2*C

  Doubling:  P = (X1 : Y1 : Z1)
      S = X1^2
      U = S + Y1
      T = X1*Z1
      Z3 = T^2
      T = U*T
      X3 = U^2 + T + a2*Z3
      Y3 = (Z3 + T)*X3 + S^2*Z3

where a2 is the field element with a2^2 = a (for a in {0, 1}, a2 = a).

See docs/MATH.md for more context.
"""

from __future__ import annotations
from dataclasses import dataclass
from typing import Optional

from .gf2m import gf_add, gf_mul, gf_square, gf_div
from . import curve
from .affine_ref import AffinePoint


@dataclass(frozen=True)
class LDPoint:
    """Projective point (X : Y : Z) in Modified Lopez-Dahab coordinates."""

    X: int
    Y: int
    Z: int

    @staticmethod
    def infinity() -> "LDPoint":
        return LDPoint(1, 0, 0)  # Z = 0 <=> point at infinity, by convention

    def is_infinity(self) -> bool:
        return self.Z == 0


def to_ld(p: AffinePoint) -> LDPoint:
    """Affine -> LD: Z = 1, exact, no field operations needed."""
    if p.is_infinity():
        return LDPoint.infinity()
    return LDPoint(p.x, p.y, 1)


def to_affine(p: LDPoint) -> AffinePoint:
    """LD -> affine: x = X/Z, y = Y/Z^2."""
    if p.is_infinity():
        return AffinePoint.infinity()
    if p.Z == 1:
        return AffinePoint(p.X, p.Y)
    z_inv = _inv(p.Z)
    z_inv2 = gf_square(z_inv)
    x = gf_mul(p.X, z_inv)
    y = gf_mul(p.Y, z_inv2)
    return AffinePoint(x, y)


def to_affine_naive(p: LDPoint) -> AffinePoint:
    """LD -> affine skipping the Y division (x = X/Z, y = Y). Only
    correct when Z == 1. Kept to demonstrate the mistake described in the
    module docstring; do not use this for anything real."""
    if p.is_infinity():
        return AffinePoint.infinity()
    z_inv = _inv(p.Z)
    x = gf_mul(p.X, z_inv)
    y = p.Y
    return AffinePoint(x, y)


def _inv(z: int) -> int:
    from .gf2m import gf_inv

    return gf_inv(z)


def ld_double(p: LDPoint, a2: int = curve.A2) -> LDPoint:
    """General point doubling. Z1 can be anything."""
    if p.is_infinity():
        return p
    X1, Y1, Z1 = p.X, p.Y, p.Z

    S = gf_square(X1)
    U = gf_add(S, Y1)
    T = gf_mul(X1, Z1)
    Z3 = gf_square(T)
    T = gf_mul(U, T)
    X3 = gf_add(gf_add(gf_square(U), T), gf_mul(a2, Z3))
    Y3 = gf_add(gf_mul(gf_add(Z3, T), X3), gf_mul(gf_square(S), Z3))

    return LDPoint(X3, Y3, Z3)


def ld_add(p: LDPoint, q: LDPoint, a2: int = curve.A2) -> LDPoint:
    """Point addition. Requires p.Z == 1; raises otherwise so misuse is
    caught early rather than producing a silently wrong result."""
    if p.is_infinity():
        return q
    if q.is_infinity():
        return p
    if p.Z != 1:
        raise ValueError(
            "ld_add: first operand must have Z == 1 (got Z = %d)" % p.Z
        )

    X1, Y1 = p.X, p.Y
    X2, Y2, Z2 = q.X, q.Y, q.Z

    if Z2 == 1 and X1 == X2:
        if Y1 == Y2:
            return ld_double(p, a2)
        return LDPoint.infinity()

    Z2sq = gf_square(Z2)
    U = gf_add(gf_mul(Z2sq, Y1), Y2)
    S = gf_add(gf_mul(Z2, X1), X2)
    T = gf_mul(Z2, S)
    Z3 = gf_square(T)
    V = gf_mul(Z3, X1)
    C = gf_add(X1, Y1)

    X3 = gf_add(gf_square(U), gf_mul(T, gf_add(gf_add(U, gf_square(S)), gf_mul(a2, T))))
    Y3 = gf_add(
        gf_mul(gf_add(V, X3), gf_add(gf_mul(T, U), Z3)),
        gf_mul(gf_square(Z3), C),
    )

    return LDPoint(X3, Y3, Z3)


def scalar_mult(k: int, p: AffinePoint, a2: int = curve.A2) -> AffinePoint:
    """k*P, left-to-right double-and-add. P stays at Z=1 the whole time."""
    if k == 0 or p.is_infinity():
        return AffinePoint.infinity()
    if k < 0:
        from .affine_ref import negate

        return scalar_mult(-k, negate(p), a2)

    fixed_p = to_ld(p)
    acc = LDPoint.infinity()
    for bit in bin(k)[2:]:
        acc = ld_double(acc, a2)
        if bit == "1":
            acc = ld_add(fixed_p, acc, a2)
    return to_affine(acc)


def scalar_mult_naive(k: int, p: AffinePoint, a2: int = curve.A2) -> AffinePoint:
    """The earlier, broken scalar multiplication: right-to-left, doubling
    the point that gets fed into ld_add as if it still had Z == 1. Raises
    once the doubled point's Z drifts away from 1. Kept for demonstration.
    """
    X1, Y1, Z1 = p.x, p.y, 1
    acc = LDPoint.infinity()
    m = k.bit_length()
    for i in range(m + 1):
        bit = (k >> i) & 1
        if bit:
            p1 = LDPoint(X1, Y1, Z1)
            if p1.Z != 1:
                raise ValueError(
                    "scalar_mult_naive: the doubled point no longer has "
                    "Z == 1 at bit %d, as expected" % i
                )
            acc = ld_add(p1, acc, a2)
        d = ld_double(LDPoint(X1, Y1, Z1), a2)
        X1, Y1, Z1 = d.X, d.Y, d.Z
    return to_affine_naive(acc)
