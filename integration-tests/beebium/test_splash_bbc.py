from __future__ import annotations

import shutil
import subprocess
import time
from pathlib import Path

import pytest

from helpers import command, wait_for_screen_text


SCREEN_START = 0x7100
SCREEN_SIZE = 0x0F00
SCREEN_CRTC_ADDRESS = SCREEN_START // 8
SPLASH_CRTC_REGISTERS = (63, 40, 49, 36, 38, 0, 12, 34, 0, 7, 32, 0, 0x0E, 0x20)

_HERE = Path(__file__).resolve()
_NIO_CONFIG_ROOT = _HERE.parents[2]
_SPLASH_DIR = _NIO_CONFIG_ROOT / "src" / "platform" / "bbc" / "splash"
_SPLASH_BUILD = _NIO_CONFIG_ROOT / "build" / "bbc" / "splash"


def type_text(bbc, text: str) -> None:
    with bbc.keyboard.text_input():
        bbc.keyboard.type(text)


def wait_for_splash_crtc(bbc, timeout: float = 5.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = bbc.crtc.state
        if (
            state.screen_start == SCREEN_CRTC_ADDRESS
            and state.hdisplayed == 40
            and state.vdisplayed == 12
            and state.max_scanline == 7
        ):
            return state
        time.sleep(0.02)
    raise TimeoutError(f"splash CRTC configuration was not observed: {bbc.crtc.state}")


@pytest.fixture(scope="session")
def splash_bbc_artifacts():
    subprocess.run(["make", "-C", str(_SPLASH_DIR), "disk"], check=True)
    screen = _SPLASH_BUILD / "SCREEN"
    disk = _SPLASH_BUILD / "splash.ssd"
    assert screen.stat().st_size == SCREEN_SIZE
    assert disk.is_file()
    return {"screen": screen, "disk": disk}


def test_bbc_splash_loads_short_mode5_screen_and_restores_mode7(
    beebium_config_nio,
    real_fujinet_config_nio,
    splash_bbc_artifacts,
    screen_evidence,
):
    """Prove the shortened bitmap is loaded, displayed, and safely removed."""
    bbc = beebium_config_nio
    fn = real_fujinet_config_nio

    boot_dir = fn.run_dir / "fujinet-data" / "boot" / "bbc"
    shutil.copy2(splash_bbc_artifacts["disk"], boot_dir / "SPLASH.ssd")

    command(bbc, "*FHOST host:/boot/bbc")
    command(bbc, "*FIN 250 SPLASH.ssd")
    command(bbc, "*FMOUNT 250 0")

    type_text(bbc, "*SPLASH\r")
    crtc = wait_for_splash_crtc(bbc)

    expected_screen = splash_bbc_artifacts["screen"].read_bytes()
    actual_screen = bytes(bbc.memory.address.peek.read(SCREEN_START, SCREEN_SIZE))
    assert actual_screen == expected_screen
    assert tuple(crtc.registers[:14]) == SPLASH_CRTC_REGISTERS

    ula = bbc.video_ula.state
    assert ula.control == 0xC4
    assert ula.teletext_mode is False
    assert tuple(ula.palette[i] for i in (0, 1, 3, 7, 9, 12, 15)) == (
        0,
        0,
        1,
        1,
        3,
        3,
        7,
    )

    frame = bbc.video.capture_frame()
    assert (frame.width, frame.height) == (160, 96)
    colours = {frame.pixels[i : i + 4] for i in range(0, len(frame.pixels), 4)}
    assert len(colours) >= 4
    if screen_evidence is not None:
        screen_evidence.note(
            "splash CRTC: 40x12 character rows, 8 rasters, start=&0E20; "
            "SCREEN matched all 3840 bytes at &7100"
        )
        screen_evidence.capture(bbc, "shortened Mode 5 splash")

    type_text(bbc, " ")
    wait_for_screen_text(bbc, ">", evidence=screen_evidence, label="MODE 7 restored")
    assert bbc.video_ula.state.teletext_mode is True
