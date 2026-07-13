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
affine_ref.py
-------------
A simple, obviously-correct affine-coordinate implementation of point
addition/doubling/scalar multiplication on

    E: y^2 + x*y = x^3 + a*x^2 + b   over GF(2^m)

This exists to act as an independent check for the projective
(lopez_dahab.py) implementation. It shares no code with it, uses one
field inversion per point operation, and follows the textbook formulas
directly.

Not optimised, not for anything where performance or side-channel
resistance matters.
"""

from __future__ import annotations
from dataclasses import dataclass
from typing import Optional

from .gf2m import gf_add, gf_mul, gf_square, gf_inv, gf_div
from . import curve


@dataclass(frozen=True)
class AffinePoint:
    x: Optional[int]  # None encodes the point at infinity
    y: Optional[int]

    @staticmethod
    def infinity() -> "AffinePoint":
        return AffinePoint(None, None)

    def is_infinity(self) -> bool:
        return self.x is None


O = AffinePoint.infinity()


def is_on_curve(p: AffinePoint, a: int = curve.A, b: int = curve.B) -> bool:
    if p.is_infinity():
        return True
    x, y = p.x, p.y
    lhs = gf_add(gf_square(y), gf_mul(x, y))
    rhs = gf_add(gf_add(gf_mul(gf_mul(x, x), x), gf_mul(a, gf_square(x))), b)
    return lhs == rhs


def negate(p: AffinePoint) -> AffinePoint:
    """-P = (x, x + y) on y^2 + xy = x^3 + a*x^2 + b."""
    if p.is_infinity():
        return p
    return AffinePoint(p.x, gf_add(p.x, p.y))


def add(p: AffinePoint, q: AffinePoint, a: int = curve.A) -> AffinePoint:
    if p.is_infinity():
        return q
    if q.is_infinity():
        return p
    if p.x == q.x and p.y != q.y:
        return O  # P + (-P) = O
    if p == q:
        return double(p, a)

    lam = gf_div(gf_add(p.y, q.y), gf_add(p.x, q.x))
    x3 = gf_add(gf_add(gf_add(gf_square(lam), lam), p.x), gf_add(q.x, a))
    y3 = gf_add(gf_mul(lam, gf_add(p.x, x3)), gf_add(x3, p.y))
    return AffinePoint(x3, y3)


def double(p: AffinePoint, a: int = curve.A) -> AffinePoint:
    if p.is_infinity():
        return p
    if p.x == 0:
        return O  # point of order 2 (not present on B-233, kept for safety)

    lam = gf_add(p.x, gf_div(p.y, p.x))
    x3 = gf_add(gf_add(gf_square(lam), lam), a)
    y3 = gf_add(gf_square(p.x), gf_mul(gf_add(lam, 1), x3))
    return AffinePoint(x3, y3)


def scalar_mult(k: int, p: AffinePoint, a: int = curve.A) -> AffinePoint:
    """Plain left-to-right double-and-add. Reference only, not constant-time."""
    if k == 0 or p.is_infinity():
        return O
    if k < 0:
        return scalar_mult(-k, negate(p), a)

    result = O
    addend = p
    while k:
        if k & 1:
            result = add(result, addend, a)
        addend = double(addend, a)
        k >>= 1
    return result
