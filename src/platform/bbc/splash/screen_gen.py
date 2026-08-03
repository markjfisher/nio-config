#!/usr/bin/env python3
"""Generate the 160x96 four-colour test image used by the splash POC.

Run directly, or let the adjacent Makefile place the result in its build
directory:

    python3 screen_gen.py --output SCREEN
"""

import argparse
from pathlib import Path

WIDTH_BYTES = 40
CHAR_ROWS = 12
RASTER_LINES = 8

# A byte filled with one Mode 5 logical pixel value:
#
# colour 0: pixels 0,0,0,0 -> 0x00
# colour 1: pixels 1,1,1,1 -> 0x0F
# colour 2: pixels 2,2,2,2 -> 0xF0
# colour 3: pixels 3,3,3,3 -> 0xFF
solid = [0x00, 0x0F, 0xF0, 0xFF]

data = bytearray()

for character_row in range(CHAR_ROWS):
    colour = (character_row // 3) & 3

    for byte_column in range(WIDTH_BYTES):
        for raster in range(RASTER_LINES):
            # Add a simple vertical pattern to make byte-column ordering clear.
            value = solid[colour]

            if byte_column % 8 == 0:
                value ^= 0xFF

            data.append(value)

assert len(data) == 3840

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=Path("SCREEN"))
args = parser.parse_args()

args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_bytes(data)
print(f"Wrote {args.output}: {len(data)} bytes")
