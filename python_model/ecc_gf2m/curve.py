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
curve.py
--------
Domain parameters for sect233r1 (NIST B-233):

    E: y^2 + x*y = x^3 + a*x^2 + b   over GF(2^233)

Standard, public SECG values (SEC 2, section 3.4; also NIST FIPS 186-4
curve B-233). Not secret, quoted here the way any ECC library hardcodes
them.
"""

from .gf2m import from_hex

M = 233

# a = 1
A = from_hex(
    "000000000000000000000000000000000000000000000000000000000001"
)
# a2 such that a2^2 == a  (a=1 => a2=1, the field's multiplicative identity)
A2 = 1

B = from_hex(
    "0066647ede6c332c7f8c0923bb58213b333b20e9ce4281fe115f7d8f90ad"
)

GX = from_hex(
    "00fac9dfcbac8313bb2139f1bb755fef65bc391f8b36f8f8eb7371fd558b"
)
GY = from_hex(
    "01006a08a41903350678e58528bebf8a0beff867a7ca36716f7e01f81052"
)

# Order of the base point G (a large prime).
N = int(
    "01000000000000000000000000000013e974e72f8a6922031d2603cfe0d7", 16
)

# Cofactor.
H = 2
