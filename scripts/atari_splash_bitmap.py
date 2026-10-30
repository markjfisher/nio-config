#!/usr/bin/env python3
"""Pack the XCF-derived logo as 128x125 pixels in four greys in ANTIC mode E.

The PNG was exported from the XCF's visible artwork against black. Normal
builds use the checked-in packed bitmap and do not require Pillow.
"""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
image = Image.open(root / "images/config-nio-splash-source.png").convert("L")
if image.size != (160, 96):
    raise ValueError("expected a 160x96 image")
# Mode E pixels are twice as wide as the screenshot's horizontal pixels.
# Compress horizontally before packing so the displayed logo keeps its shape.
image = image.resize((104, 125), Image.Resampling.LANCZOS)
canvas = Image.new("L", (128, 125))
canvas.paste(image, (12, 0))
image = canvas
bitmap = bytearray()
for row in range(125):
    for col in range(0, 128, 4):
        value = 0
        for pixel in range(4):
            level = min(3, (image.getpixel((col + pixel, row)) * 4) // 256)
            value = (value << 2) | level
        bitmap.append(value)
(root / "src/atari-bootstrap/assets/splash.bin").write_bytes(bitmap)
