#!/usr/bin/env python3
"""Reject an Atari XEX whose load chunks overlap the boot bitmap."""
import sys
from pathlib import Path


def check(data):
    if not data:
        raise ValueError("empty XEX")
    pos = 0
    while pos < len(data):
        if data[pos:pos + 2] == b"\xff\xff":
            pos += 2
        if pos + 4 > len(data):
            raise ValueError("truncated XEX segment header")
        start = int.from_bytes(data[pos:pos + 2], "little")
        end = int.from_bytes(data[pos + 2:pos + 4], "little")
        pos += 4
        if end < start or pos + end - start + 1 > len(data):
            raise ValueError("invalid XEX segment length")
        if start <= 0xaf9f and end >= 0xa000:
            raise ValueError(f"XEX segment ${start:04X}-${end:04X} overlaps splash $A000-$AF9F")
        pos += end - start + 1


if __name__ == "__main__":
    try:
        check(Path(sys.argv[1]).read_bytes())
    except (OSError, ValueError, IndexError) as exc:
        raise SystemExit(str(exc))
