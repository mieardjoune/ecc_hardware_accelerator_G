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
gf2m.py
-------
Arithmetic in the binary field GF(2^233) used by curve sect233r1 (NIST
B-233), in polynomial basis: bit i of a Python integer is the coefficient
of x^i.

Reduction polynomial: f(x) = x^233 + x^74 + 1

Every function here is a plain, unoptimised version of the textbook
algorithm, written to be easy to read and to compare against the RTL in
src/. Not constant time, not for anything security-sensitive: this is a
reference for checking hardware, not a cryptography library.
"""

from __future__ import annotations

M_DEGREE = 233
# f(x) = x^233 + x^74 + 1
REDUCTION_POLY = (1 << 233) | (1 << 74) | 1


def deg(a: int) -> int:
    """Degree of polynomial `a` (deg(0) == -1)."""
    return a.bit_length() - 1


def gf_add(a: int, b: int) -> int:
    """Addition (== subtraction) in GF(2^m): bitwise XOR."""
    return a ^ b


def gf_mul(a: int, b: int, modulus: int = REDUCTION_POLY, m: int = M_DEGREE) -> int:
    """Multiply two field elements and reduce modulo `modulus`.

    Right-to-left shift-and-add: consume the bits of `a`, doubling `b`
    (and reducing it) each step.
    """
    result = 0
    top_bit = 1 << m
    while a:
        if a & 1:
            result ^= b
        a >>= 1
        b <<= 1
        if b & top_bit:
            b ^= modulus
    return result


def gf_square(a: int, modulus: int = REDUCTION_POLY, m: int = M_DEGREE) -> int:
    """Square a field element.

    Squaring in GF(2^m) is F2-linear (the Frobenius map), so it can be done
    by spreading the bits of `a` apart (inserting a 0 between every bit) and
    then reducing -- this is the well known "bit-spread" squaring trick and
    is much cheaper than a generic multiplication.
    """
    spread = 0
    i = 0
    while a:
        if a & 1:
            spread |= 1 << (2 * i)
        a >>= 1
        i += 1
    return _reduce(spread, modulus, m)


def _reduce(value: int, modulus: int = REDUCTION_POLY, m: int = M_DEGREE) -> int:
    """Reduce an over-wide polynomial modulo `modulus` (degree m)."""
    while deg(value) >= m:
        value ^= modulus << (deg(value) - m)
    return value


def gf_frobenius(a: int, k: int, modulus: int = REDUCTION_POLY, m: int = M_DEGREE) -> int:
    """Compute a^(2^k) by repeated squaring (k squarings)."""
    for _ in range(k):
        a = gf_square(a, modulus, m)
    return a


def gf_pow(a: int, e: int, modulus: int = REDUCTION_POLY, m: int = M_DEGREE) -> int:
    """Generic square-and-multiply exponentiation, a^e."""
    if e < 0:
        raise ValueError("negative exponent")
    result = 1
    base = a
    while e:
        if e & 1:
            result = gf_mul(result, base, modulus, m)
        base = gf_square(base, modulus, m)
        e >>= 1
    return result


def gf_inv_fermat(a: int, modulus: int = REDUCTION_POLY, m: int = M_DEGREE) -> int:
    """Inverse via Fermat's little theorem: a^-1 = a^(2^m - 2).

    Simple, obviously-correct reference implementation used to cross-check
    the faster Itoh-Tsujii inversion below.
    """
    if a == 0:
        raise ZeroDivisionError("division by zero in GF(2^m)")
    return gf_pow(a, (1 << m) - 2, modulus, m)


def gf_inv_itoh_tsujii(a: int, modulus: int = REDUCTION_POLY, m: int = M_DEGREE) -> int:
    """Itoh-Tsujii inversion, a^-1 = a^(2^m - 2), using an addition chain.

    Builds a^(2^(m-1) - 1) with O(log m) multiplications instead of
    O(m), then squares once more to get a^(2^m - 2) = a^-1. This is the
    classical Itoh-Tsujii construction (Itoh & Tsujii, 1988), derived here
    directly from the bits of (m-1).
    """
    if a == 0:
        raise ZeroDivisionError("division by zero in GF(2^m)")

    e = m - 1  # exponent we build up to: a^(2^e - 1)
    bits = bin(e)[2:]  # MSB-first bits of (m-1)

    s = a          # invariant: s == a^(2^k - 1)
    k = 1
    for bit in bits[1:]:
        # "double" step: s <- s^(2^k) * s  ==>  a^(2^(2k) - 1)
        s = gf_mul(gf_frobenius(s, k, modulus, m), s, modulus, m)
        k *= 2
        if bit == "1":
            # "increment" step: s <- s^2 * a ==> a^(2^(k+1) - 1)
            s = gf_mul(gf_frobenius(s, 1, modulus, m), a, modulus, m)
            k += 1
    assert k == e
    # s == a^(2^(m-1) - 1); one more squaring gives a^(2^m - 2) = a^-1
    return gf_frobenius(s, 1, modulus, m)


# Default inversion used by the rest of the codebase.
gf_inv = gf_inv_itoh_tsujii


def gf_div(a: int, b: int, modulus: int = REDUCTION_POLY, m: int = M_DEGREE) -> int:
    """a / b == a * b^-1."""
    return gf_mul(a, gf_inv(b, modulus, m), modulus, m)


def to_hex(a: int, nbits: int = M_DEGREE) -> str:
    return format(a, "0%dx" % ((nbits + 3) // 4))


def from_hex(s: str) -> int:
    return int(s, 16)
