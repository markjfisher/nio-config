from __future__ import annotations

import time

from beebium.client.screen import dump_screen, read_mode7_screen

from helpers import command, wait_for_screen_text

ARROW_DOWN = (2, 9)


def type_text(bbc, text: str) -> None:
    with bbc.keyboard.text_input():
        bbc.keyboard.type(text)


def tap_matrix(bbc, row: int, column: int, hold: float = 0.05) -> None:
    bbc.keyboard.matrix_down(row, column)
    time.sleep(hold)
    bbc.keyboard.matrix_up(row, column)
    time.sleep(hold)


def press_key(bbc, text: str, wait: float = 0.15) -> None:
    type_text(bbc, text)
    time.sleep(wait)


def row_with_text(bbc, needle: str) -> int:
    wanted = needle.upper()
    for index, row in enumerate(read_mode7_screen(bbc)):
        if wanted in row.upper():
            return index
    raise AssertionError(f"{needle!r} not found on screen\n{dump_screen(bbc)}")


def select_browse_entry(bbc, needle: str) -> None:
    row = row_with_text(bbc, needle)
    first_entry_row = 9
    if row < first_entry_row:
        raise AssertionError(f"{needle!r} appeared outside browse entries\n{dump_screen(bbc)}")
    for _ in range(row - first_entry_row):
        tap_matrix(bbc, *ARROW_DOWN)


def assert_slots_page_clean(screen: str) -> None:
    assert "Drive Mappings" in screen
    assert "Slots" in screen
    assert "fujinet.diller.org" not in screen
    assert "fujinet.online" not in screen


def test_config_nio_bbc_browse_assign_mount_real_fujinet(
    beebium_config_nio, real_fujinet_config_nio, screen_evidence
):
    bbc = beebium_config_nio

    command(bbc, "*FUJI")
    type_text(bbc, "*CONFNIO\r")
    wait_for_screen_text(bbc, "sd0:/", evidence=screen_evidence, label="hosts initial")
    wait_for_screen_text(bbc, "fujinet.diller.org")

    press_key(bbc, "E")
    type_text(bbc, "\x7f\x7f\x7f\x7f\x7fhost:/\r")
    wait_for_screen_text(bbc, "host:/", evidence=screen_evidence, label="hosts edited")

    press_key(bbc, "\r", wait=0.5)
    wait_for_screen_text(bbc, "cfg", evidence=screen_evidence, label="browse root")
    select_browse_entry(bbc, "cfg")
    press_key(bbc, "\r", wait=0.5)

    wait_for_screen_text(bbc, "images", evidence=screen_evidence, label="browse cfg")
    select_browse_entry(bbc, "images")
    press_key(bbc, "\r", wait=0.5)

    wait_for_screen_text(bbc, "longer-navtest.ssd", evidence=screen_evidence, label="browse image")
    select_browse_entry(bbc, "longer-navtest.ssd")
    press_key(bbc, "A")
    wait_for_screen_text(bbc, "Assign file to slot")
    press_key(bbc, "N", wait=0.4)  # slots 8-15
    press_key(bbc, "N", wait=0.4)  # slots 16-23
    rows = read_mode7_screen(bbc)
    assert "16" in rows[12]
    assert "23" in rows[19]
    if screen_evidence is not None:
        screen_evidence.capture(
            bbc, "assign third sparse page", screen=dump_screen(bbc)
        )
    press_key(bbc, "3", wait=0.5)  # visible row 3 => absolute slot 19
    wait_for_screen_text(bbc, "longer-navtest.ssd", evidence=screen_evidence, label="slot assigned")

    press_key(bbc, "S", wait=0.5)
    slots_screen = wait_for_screen_text(
        bbc,
        "Drive Mappings",
        evidence=screen_evidence,
        label="slots before mapping",
    )
    assert_slots_page_clean(slots_screen)

    # The catalogue screen has independent paging state, so move it to the
    # page containing slot 19 before mapping visible row 3.
    press_key(bbc, "\t")
    press_key(bbc, "N", wait=0.4)
    press_key(bbc, "N", wait=0.4)
    rows = read_mode7_screen(bbc)
    assert "19" in rows[15]
    assert "longer-navtest.ssd" in rows[15]
    press_key(bbc, "1", wait=0.5)  # selected slot 19 -> drive 1
    slots_screen = wait_for_screen_text(
        bbc,
        "D1 S19",
        evidence=screen_evidence,
        label="slots drive1 mapped",
    )
    assert "longer-navtest.ssd" in slots_screen
    assert_slots_page_clean(slots_screen)

    press_key(bbc, "M", wait=1.0)
    assert real_fujinet_config_nio.wait_for_log("dev=0xFC cmd=0x01", timeout=4.0), (
        real_fujinet_config_nio.log_text()[-4000:]
    )
    command(bbc, "*. :1.$")
    wait_for_screen_text(bbc, "HELLO", evidence=screen_evidence, label="mounted drive catalogue")


def test_config_nio_bbc_large_directory_renders_real_fujinet(beebium_config_nio, screen_evidence):
    bbc = beebium_config_nio

    command(bbc, "*FUJI")
    type_text(bbc, "*CONFNIO\r")
    wait_for_screen_text(bbc, "sd0:/")

    press_key(bbc, "E")
    type_text(bbc, "\x7f\x7f\x7f\x7f\x7fhost:/\r")
    wait_for_screen_text(bbc, "host:/", evidence=screen_evidence, label="large hosts edited")

    press_key(bbc, "\r", wait=0.5)
    wait_for_screen_text(bbc, "bbc", evidence=screen_evidence, label="large browse root")
    select_browse_entry(bbc, "bbc")
    press_key(bbc, "\r", wait=0.5)

    screen = wait_for_screen_text(
        bbc,
        "basic2.ssd",
        evidence=screen_evidence,
        label="large browse bbc",
    )
    assert "fs.ssd" in screen
    assert "fstest.ssd" in screen
