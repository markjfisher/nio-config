from __future__ import annotations

import time

import pytest

from beebium.client.screen import dump_screen, read_mode7_screen

from helpers import command, wait_for_screen_text

ARROW_DOWN = (2, 9)
ARROW_LEFT = (1, 9)
ARROW_RIGHT = (7, 9)


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


def wait_for_screen_without_text(bbc, text: str, timeout: float = 8.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if text not in dump_screen(bbc):
            return
        time.sleep(0.02)
    raise TimeoutError(f"Text {text!r} remained on screen\n{dump_screen(bbc)}")


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


def test_config_nio_bbc_cli_escape_prints_escape(beebium_config_nio):
    """Control case: Escape at the normal CLI must print ``Escape``."""
    bbc = beebium_config_nio

    tap_matrix(bbc, 7, 0, hold=0.5)
    time.sleep(0.5)
    screen = dump_screen(bbc)
    assert "Escape" in screen, screen


def test_config_nio_bbc_escape_after_transient_fls_prints_escape(beebium_config_nio):
    """A non-CONFNIO transient utility must also restore CLI Escape handling."""
    bbc = beebium_config_nio

    command(bbc, "*FLS")
    tap_matrix(bbc, 7, 0, hold=0.5)
    time.sleep(0.5)
    screen = dump_screen(bbc)
    assert "Escape" in screen, screen


def test_config_nio_bbc_escape_after_cc65_keycode_prints_escape(beebium_config_nio):
    """The small C/CC65 KEYCODE transient must restore CLI Escape handling."""
    bbc = beebium_config_nio

    type_text(bbc, "*KEYCODE\r")
    wait_for_screen_text(bbc, "KEYCODE")
    # Drive the physical key long enough for MOS keyboard scanning.  The
    # type-ahead path is reliable for CLI text but can be consumed before a
    # transient program's cgetc() poll sees it.
    tap_matrix(bbc, 1, 0, hold=0.5)
    time.sleep(1.0)
    tap_matrix(bbc, 7, 0, hold=0.5)
    time.sleep(1.0)
    screen = dump_screen(bbc)
    assert "Escape" in screen, screen


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
    wait_for_screen_text(bbc, "Path: /cfg/", evidence=screen_evidence,
                         label="entered cfg directory")
    select_browse_entry(bbc, "images")
    press_key(bbc, "\r", wait=0.5)

    wait_for_screen_text(bbc, "longer-navtest.ssd", evidence=screen_evidence, label="browse image")
    wait_for_screen_text(bbc, "Path: /cfg/images/", evidence=screen_evidence,
                         label="entered images directory")
    select_browse_entry(bbc, "longer-navtest.ssd")
    press_key(bbc, "A")
    wait_for_screen_text(bbc, "Assign file to slot")
    press_key(bbc, "N", wait=0.4)  # slots 8-15
    wait_for_screen_text(bbc, "blank.ssd")
    rows = read_mode7_screen(bbc)
    assert "11" in rows[15]
    assert "blank.ssd" in rows[15]
    catalogue_calls = real_fujinet_config_nio.log_text().count("dev=0xF2 cmd=0x04")
    press_key(bbc, "P", wait=0.4)  # slots 0-7
    wait_for_screen_without_text(bbc, "blank.ssd")
    assert real_fujinet_config_nio.log_text().count("dev=0xF2 cmd=0x04") == catalogue_calls
    rows = read_mode7_screen(bbc)
    assert "3" in rows[15]
    assert rows[15][35] == " ", rows[15]
    press_key(bbc, "N", wait=0.4)  # slots 8-15
    assert real_fujinet_config_nio.log_text().count("dev=0xF2 cmd=0x04") == catalogue_calls
    press_key(bbc, "N", wait=0.4)  # slots 16-23
    assert real_fujinet_config_nio.log_text().count("dev=0xF2 cmd=0x04") > catalogue_calls
    rows = read_mode7_screen(bbc)
    assert "16" in rows[12]
    assert "23" in rows[19]
    if screen_evidence is not None:
        screen_evidence.capture(
            bbc, "assign third sparse page", screen=dump_screen(bbc)
        )
    press_key(bbc, "3", wait=0.5)  # visible row 3 => absolute slot 19
    wait_for_screen_text(bbc, "longer-navtest.ssd", evidence=screen_evidence, label="slot assigned")
    slot_record = (
        real_fujinet_config_nio.run_dir
        / "fujinet-data"
        / "FujiNet"
        / "app-store"
        / "v1"
        / "config-nio"
        / "slot-019.bin"
    ).read_bytes()
    assert slot_record == b"\x01\x00host:/cfg/images/longer-navtest.ssd"

    press_key(bbc, "S", wait=0.5)
    slots_screen = wait_for_screen_text(
        bbc,
        "Drive Mappings",
        evidence=screen_evidence,
        label="slots before mapping",
    )
    assert_slots_page_clean(slots_screen)
    # The boot image is an active DiskService mount, not a catalogue mapping.
    # It must still be visible in the drive pane without inventing a slot entry.
    assert "D0 BOOT" in slots_screen
    assert "FN-BOOT.ssd" in slots_screen

    # The catalogue screen has independent paging state, so move it to the
    # page containing slot 19 before mapping visible row 3.
    press_key(bbc, "\t")
    press_key(bbc, "N", wait=0.4)
    press_key(bbc, "N", wait=0.4)
    rows = read_mode7_screen(bbc)
    assert "19" in rows[15]
    assert "longer-navtest.ssd" in rows[15]
    press_key(bbc, "0", wait=0.5)  # selected slot 19 replaces boot disk in drive 0
    slots_screen = wait_for_screen_text(
        bbc,
        "D0 S19",
        evidence=screen_evidence,
        label="slots drive0 mapped",
    )
    assert "longer-navtest.ssd" in slots_screen
    assert_slots_page_clean(slots_screen)

    press_key(bbc, "M", wait=1.0)
    assert real_fujinet_config_nio.wait_for_log("dev=0xFC cmd=0x01", timeout=4.0), (
        real_fujinet_config_nio.log_text()[-4000:]
    )
    command(bbc, "*.")
    wait_for_screen_text(bbc, "HELLO", evidence=screen_evidence, label="mounted drive catalogue")


def test_config_nio_bbc_shows_fboot_runtime_mount(
    beebium_config_nio, real_fujinet_config_nio, screen_evidence
):
    bbc = beebium_config_nio

    command(bbc, "*FUJI")
    command(bbc, "*FBOOT 3")
    type_text(bbc, "*CONFNIO\r")
    wait_for_screen_text(bbc, "sd0:/", evidence=screen_evidence, label="hosts initial")
    wait_for_screen_text(bbc, "fujinet.diller.org")

    press_key(bbc, "S", wait=0.5)
    screen = wait_for_screen_text(
        bbc,
        "Drive Mappings",
        evidence=screen_evidence,
        label="FBOOT runtime mapping",
    )
    assert "D3 BOOT FN-BOOT.ssd" in screen

    appstore = (
        real_fujinet_config_nio.run_dir
        / "fujinet-data"
        / "FujiNet"
        / "app-store"
        / "v1"
        / "config-nio"
    )
    mappings_path = appstore / "mappings.bin"
    mappings = mappings_path.read_bytes() if mappings_path.exists() else b""
    assert len(mappings) == 0 or mappings[0] == 1
    if mappings:
        assert mappings[7:9] == b"\x00\x00"  # drive 3 remains catalogue-unassigned


@pytest.mark.parametrize("exit_key", ("Q", "M"))
def test_config_nio_bbc_escape_after_exit_returns_cleanly_to_cli(
    beebium_config_nio, screen_evidence, exit_key
):
    """The application must not leave its Escape handling active after exit."""
    bbc = beebium_config_nio

    type_text(bbc, "*CONFNIO\r")
    wait_for_screen_text(bbc, "sd0:/", evidence=screen_evidence, label="config-nio")

    # Use matrix timing here so the exit key is definitely consumed by the
    # application's cgetc(), rather than merely remaining in type-ahead.
    if exit_key == "Q":
        tap_matrix(bbc, 1, 0)
    else:
        tap_matrix(bbc, 6, 5)
    time.sleep(1.0)
    tap_matrix(bbc, 7, 0, hold=0.5)
    time.sleep(1.0)

    screen = dump_screen(bbc)
    if screen_evidence is not None:
        screen_evidence.capture(bbc, "escape after quit")
    assert "CONFNIO" not in screen
    assert "HOSTS" not in screen
    assert "BROWSE" not in screen
    assert "SLOTS" not in screen
    assert "Bad program" not in screen
    assert "Escape" in screen, screen
    rows = read_mode7_screen(bbc)
    assert any(row.strip() == ">" for row in rows), screen


def test_config_nio_bbc_does_not_reuse_stale_uri_for_unmounted_drive(
    beebium_config_nio, screen_evidence
):
    """A failed LIST_MOUNTS lookup must clear that drive's display buffer."""
    bbc = beebium_config_nio

    command(bbc, "*FUJI")
    type_text(bbc, "*CONFNIO\r")
    wait_for_screen_text(bbc, "sd0:/", label="hosts initial")
    wait_for_screen_text(bbc, "fujinet.diller.org")

    # Use the same known image twice.  The second assignment leaves its URI
    # in the shared uri_buf, where it used to be mistaken for a runtime mount
    # on D1 when LIST_MOUNTS returned no D1 entry.
    press_key(bbc, "E")
    type_text(bbc, "\x7f\x7f\x7f\x7f\x7fhost:/\r")
    wait_for_screen_text(bbc, "host:/", label="hosts edited")
    press_key(bbc, "\r", wait=0.5)
    wait_for_screen_text(bbc, "cfg", label="browse root")
    select_browse_entry(bbc, "cfg")
    press_key(bbc, "\r", wait=0.5)
    wait_for_screen_text(bbc, "images", label="browse cfg")
    select_browse_entry(bbc, "images")
    press_key(bbc, "\r", wait=0.5)
    wait_for_screen_text(bbc, "longer-navtest.ssd", label="browse image")
    select_browse_entry(bbc, "longer-navtest.ssd")

    press_key(bbc, "A")
    wait_for_screen_text(bbc, "Assign file to slot")
    press_key(bbc, "5", wait=0.5)
    wait_for_screen_text(bbc, "longer-navtest.ssd", label="slot 5 assigned")

    # The browse selection remains on the same file after returning from the
    # assignment dialog, so assign it again to a higher slot.
    press_key(bbc, "A")
    wait_for_screen_text(bbc, "Assign file to slot")
    press_key(bbc, "N", wait=0.4)  # slots 8-15
    press_key(bbc, "4", wait=0.5)  # absolute slot 12
    wait_for_screen_text(bbc, "longer-navtest.ssd", label="slot 12 assigned")

    press_key(bbc, "S", wait=0.5)
    screen = wait_for_screen_text(
        bbc, "Drive Mappings", evidence=screen_evidence, label="slots page"
    )
    assert "D0 BOOT" in screen
    assert "D1 BOOT" not in screen


def test_config_nio_bbc_slots_cached_previous_page_renders_all_rows(
    beebium_config_nio, screen_evidence
):
    bbc = beebium_config_nio

    command(bbc, "*FUJI")
    command(bbc, "*FHOST host:/cfg/images")
    command(bbc, "*FIN 0 blank.ssd")
    command(bbc, "*FIN 3 ctests.ssd")
    # This long URI fills the slot row when rendered with its two-digit
    # index.  Paging back to the one-digit page must clear the entire row.
    command(bbc, "*FIN 10 longer-navtest.ssd")
    command(bbc, "*FIN 20 bwc.ssd")

    type_text(bbc, "*CONFNIO\r")
    wait_for_screen_text(bbc, "sd0:/")
    press_key(bbc, "S", wait=0.5)
    wait_for_screen_text(bbc, "Drive Mappings", evidence=screen_evidence,
                         label="slots cache page 0")
    press_key(bbc, "\t")

    # Fetch page 8-15, then return to the cached page 0-7.  Slot 10's URI
    # occupies the full row on the first page, so slot 2 exposes stale text.
    tap_matrix(bbc, *ARROW_RIGHT)
    time.sleep(0.5)
    rows = read_mode7_screen(bbc)
    assert "10" in rows[14]
    assert "longer-navtest.ssd" in rows[14]
    tap_matrix(bbc, *ARROW_LEFT)
    time.sleep(0.5)
    rows = read_mode7_screen(bbc)
    assert rows[14][8:37].strip() == "", rows[14]

    # Continue paging forward and back to exercise the two-page cache with
    # a non-adjacent sparse page as well.
    tap_matrix(bbc, *ARROW_RIGHT)
    time.sleep(0.5)
    tap_matrix(bbc, *ARROW_RIGHT)
    time.sleep(0.5)
    rows = read_mode7_screen(bbc)
    for slot in range(16, 24):
        assert str(slot) in rows[12 + slot - 16], rows[12 + slot - 16]

    # Page 8-15 should now be served from the two-page cache rather than
    # refetched. Every row must retain its index after the redraw.
    tap_matrix(bbc, *ARROW_LEFT)
    time.sleep(0.5)
    rows = read_mode7_screen(bbc)
    if screen_evidence is not None:
        screen_evidence.capture(bbc, "slots cached previous page")
    for slot in range(8, 16):
        assert str(slot) in rows[12 + slot - 8], rows[12 + slot - 8]



def test_config_nio_bbc_assigning_slot_to_drive_one_keeps_mappings_intact(
    beebium_config_nio, screen_evidence
):
    """Mapping a visible slot to D1 must not corrupt the allocation screen."""
    bbc = beebium_config_nio

    command(bbc, "*FUJI")
    command(bbc, "*FHOST host:/cfg/images")
    command(bbc, "*FIN 3 ctests.ssd")

    type_text(bbc, "*CONFNIO\r")
    wait_for_screen_text(bbc, "sd0:/")
    press_key(bbc, "S", wait=0.5)
    screen = wait_for_screen_text(
        bbc, "Drive Mappings", evidence=screen_evidence, label="slots before D1 mapping"
    )
    assert "D0 BOOT" in screen
    assert "D1 --" in screen
    assert_slots_page_clean(screen)

    # Switch to the slots pane, select slot 3, and assign it to drive 1.
    press_key(bbc, "\t")
    for _ in range(3):
        tap_matrix(bbc, *ARROW_DOWN)
    press_key(bbc, "1", wait=0.5)

    screen = wait_for_screen_text(
        bbc,
        "D1 S3",
        evidence=screen_evidence,
        label="slot 3 mapped to drive 1",
    )
    rows = read_mode7_screen(bbc)
    assert "D0 BOOT" in rows[7], rows[7]
    assert "D1 S3" in rows[8], rows[8]
    assert "D2 --" in rows[9], rows[9]
    assert "D3 --" in rows[10], rows[10]
    assert "Drive Mappings" in screen
    assert "Slots" in screen
    assert_slots_page_clean(screen)


def test_config_nio_bbc_shows_cli_mapping_and_canonical_slot_uri(
    beebium_config_nio, real_fujinet_config_nio, screen_evidence
):
    bbc = beebium_config_nio

    command(bbc, "*FUJI")
    command(bbc, "*FHOST host:/cfg/images")
    command(bbc, "*FIN 100 longer-navtest.ssd")
    command(bbc, "*FMOUNT 100 1")
    command(bbc, "*. :1")
    wait_for_screen_text(
        bbc, "HELLO", evidence=screen_evidence, label="cli mapping mounted"
    )

    appstore = (
        real_fujinet_config_nio.run_dir
        / "fujinet-data"
        / "FujiNet"
        / "app-store"
        / "v1"
        / "config-nio"
    )
    assert (appstore / "slot-100.bin").read_bytes() == (
        b"\x01\x00host:/cfg/images/longer-navtest.ssd"
    )
    mappings = (appstore / "mappings.bin").read_bytes()
    assert len(mappings) == 17
    assert mappings[0] == 1
    assert mappings[3:5] == bytes((1, 100))  # drive 1: valid/RW, slot 100

    # Replace the live disk without changing the persisted catalogue mapping.
    # Mount+exit below must therefore reconstruct and execute "FMOUNT 100 1",
    # rather than merely leaving the earlier CLI mount in place.
    command(bbc, "*FBOOT 1")

    type_text(bbc, "*CONFNIO\r")
    wait_for_screen_text(bbc, "sd0:/")
    press_key(bbc, "S", wait=0.5)
    screen = wait_for_screen_text(
        bbc,
        "D1 S100 W",
        evidence=screen_evidence,
        label="cli mapping shown in config",
    )
    assert "longer-navtest.ssd" in screen

    rows = read_mode7_screen(bbc)
    drive1 = rows[8]
    drive2 = rows[9]
    # A three-digit slot must leave the template's right-edge graphics cells
    # untouched, exactly as an empty drive row does.
    assert drive1[-2:] == drive2[-2:], (drive1, drive2)

    mount_calls = real_fujinet_config_nio.log_text().count("dev=0xFC cmd=0x01")
    press_key(bbc, "M", wait=1.0)
    assert real_fujinet_config_nio.log_text().count("dev=0xFC cmd=0x01") > mount_calls
    command(bbc, "*. :1")
    wait_for_screen_text(
        bbc, "HELLO", evidence=screen_evidence, label="three-digit mapping remounted"
    )

    command(bbc, "*FUMOUNT 1")
    mappings = (appstore / "mappings.bin").read_bytes()
    assert mappings[3:5] == b"\x00\x00"
    command(bbc, "*. :1")
    wait_for_screen_text(
        bbc, "No disk", evidence=screen_evidence, label="cli mapping unmounted"
    )


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
