"""The splash must survive every executable load chunk."""
import unittest
from common import REPO
from check_atari_splash_layout import check


def segment(start, end):
    return start.to_bytes(2, "little") + end.to_bytes(2, "little") + bytes(end - start + 1)


class SplashLayout(unittest.TestCase):
    def test_bitmap_has_four_shades(self):
        bitmap = (REPO / "src/atari-bootstrap/assets/splash.bin").read_bytes()
        self.assertEqual(len(bitmap), 4000)
        self.assertEqual({(byte >> shift) & 3 for byte in bitmap
                          for shift in (6, 4, 2, 0)}, {0, 1, 2, 3})

    def test_checks_actual_xex_and_overlap_boundaries(self):
        for xex in ("build/atari/bin/config-nio.xex",
                    "build/atari-banked/bin/config-nio.xex"):
            path = REPO / xex
            if path.exists():
                check(path.read_bytes())
        check(b"\xff\xff" + segment(0x9ffc, 0x9fff) + segment(0xafa0, 0xafa1))
        for start, end in ((0x9fff, 0xa000), (0xa000, 0xa000),
                           (0xaf9f, 0xafa0), (0xa100, 0xa101)):
            with self.subTest(start=start, end=end), self.assertRaises(ValueError):
                check(b"\xff\xff" + segment(start, end))
        with self.assertRaises(ValueError):
            check(b"\xff\xff\x00")
        with self.assertRaises(ValueError):
            check(b"")
