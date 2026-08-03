#!/usr/bin/env python3
"""Generate BBC Mode 5 screen data for the splash POC.

With no input image, generate the original synthetic test pattern. With a PNG
input, convert an exact 160x96 four-level grayscale image:

    python3 screen_gen.py --output SCREEN
    python3 screen_gen.py --input image.png --output SCREEN
"""

import argparse
from pathlib import Path

from PIL import Image

WIDTH_BYTES = 40
CHAR_ROWS = 12
RASTER_LINES = 8
WIDTH = WIDTH_BYTES * 4
HEIGHT = CHAR_ROWS * RASTER_LINES
SCREEN_SIZE = WIDTH_BYTES * CHAR_ROWS * RASTER_LINES

# A byte filled with one Mode 5 logical pixel value:
#
# colour 0: pixels 0,0,0,0 -> 0x00
# colour 1: pixels 1,1,1,1 -> 0x0F
# colour 2: pixels 2,2,2,2 -> 0xF0
# colour 3: pixels 3,3,3,3 -> 0xFF
solid = [0x00, 0x0F, 0xF0, 0xFF]


def pack_pixels(pixels: list[int]) -> int:
    """Pack four left-to-right Mode 5 pixels into one screen byte."""
    value = 0
    for pixel, colour in enumerate(pixels):
        bit = 3 - pixel
        value |= (colour & 1) << bit
        value |= ((colour >> 1) & 1) << (bit + 4)
    return value

def synthetic_screen() -> bytearray:
    data = bytearray()
    for character_row in range(CHAR_ROWS):
        colour = (character_row // 3) & 3

        for byte_column in range(WIDTH_BYTES):
            for raster in range(RASTER_LINES):
                # Add a simple vertical pattern to make byte-column ordering
                # clear while retaining solid test colours.
                value = solid[colour]
                if byte_column % 8 == 0:
                    value ^= 0xFF
                data.append(value)
    return data

def png_screen(input_path: Path) -> bytearray:
    with Image.open(input_path) as image:
        if image.size != (WIDTH, HEIGHT):
            raise ValueError(
                f"{input_path} must be exactly {WIDTH}x{HEIGHT}, got {image.size}"
            )
        grayscale = image.convert("RGB")
        pixels = list(grayscale.get_flattened_data())

    if any(red != green or red != blue for red, green, blue in pixels):
        raise ValueError(f"{input_path} must contain grayscale pixels")

    levels = sorted({red for red, _, _ in pixels})
    if not 1 <= len(levels) <= 4:
        raise ValueError(
            f"{input_path} must contain one to four grayscale levels, got {levels}"
        )

    # Preserve absolute black/white for diagnostic images with fewer than four
    # levels while mapping the supplied four source levels to 0..3.
    level_to_colour = {level: round(level * 3 / 255) for level in levels}
    logical_pixels = [level_to_colour[red] for red, _, _ in pixels]
    data = bytearray()

    # The custom CRTC layout used by the splash displays each byte column's
    # eight raster bytes contiguously before advancing horizontally.
    for character_row in range(CHAR_ROWS):
        y_start = character_row * RASTER_LINES
        for byte_column in range(WIDTH_BYTES):
            x = byte_column * 4
            for raster in range(RASTER_LINES):
                y = y_start + raster
                row_start = y * WIDTH
                data.append(pack_pixels(logical_pixels[row_start + x : row_start + x + 4]))
    return data


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--input", type=Path, help="160x96 four-level grayscale PNG")
parser.add_argument("--output", type=Path, default=Path("SCREEN"))
args = parser.parse_args()

data = png_screen(args.input) if args.input else synthetic_screen()
assert len(data) == SCREEN_SIZE
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_bytes(data)
print(f"Wrote {args.output}: {len(data)} bytes")
