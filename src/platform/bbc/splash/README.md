# BBC shortened-screen splash proof of concept

This directory contains a standalone 6502 splash application and a generated
test image. It is intentionally separate from the main `config-nio` link: the
eventual loader must remain small, display the splash, load `CONFNIO` at
`&1900`, and transfer control to it.

The current proof of concept loads `SCREEN` at `&7100`, displays it as a
160-by-96 Mode 5 bitmap, waits for a key, and restores MODE 7 before returning.
Only 3,840 bytes of screen RAM are used:

```text
&6931              splash program
&7100..&7FFF       SCREEN (40 bytes x 8 rasters x 12 rows)
```

The CRTC retains normal PAL frame timing. Register R6 limits the displayed
bitmap to 12 character rows, while R12/R13 point the display at `&7100 / 8 =
&0E20`. The unused part of the frame is border rather than allocated screen
memory.

Build the program and generated image:

```sh
make -C src/platform/bbc/splash
```

Build a standalone DFS image containing `SPLASH` and `SCREEN`:

```sh
make -C src/platform/bbc/splash disk
```

The outputs are placed under `build/bbc/splash/`. The disk can be mounted and
the proof run with:

```text
*SPLASH
```

The Beebium integration test verifies the loaded bytes, CRTC registers, Video
ULA mode and palette, rendered frame, and restoration to MODE 7 after a key.
Run it from the repository root with:

```sh
./integration-tests/beebium/run_pytest.sh \
  test_splash_bbc.py::test_bbc_splash_loads_short_mode5_screen_and_restores_mode7 -q
```
