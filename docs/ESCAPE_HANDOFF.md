# BBC Escape-after-CONFNIO investigation

## Problem

After `*CONFNIO` exits with `Q` or `M`, pressing Escape at the BBC CLI does
not behave like a normal CLI Escape (`Escape` followed by a prompt). It may
be swallowed, print unexpected output, or re-enter application behaviour.

## Resolution

Two independent lifecycle bugs were found.

First, the BBC assembly in `fujinet-nio-lib` cleared three session records in
`_fn_init`, while the CC65 declaration allocated only two. The 14-byte overrun
reached CC65's BRK-handler state and cleared both the saved BRKV and the
"installed" flag. The BBC assembly session count now matches the C allocation.

Second, even with BRKV restored correctly, pressing Escape after CONFNIO could
report `Bad program`. This was not an Escape-handler leak or a hardware-stack
leak. CONFNIO loads at `$1900` and occupies language RAM, including BBC BASIC's
program area. Returning to the existing BASIC instance leaves it examining
overwritten program state when it next handles an error. Issuing `NEW` before
Escape proved this: Escape then behaved normally.

The BBC CC65 runtime now has a post-cleanup exit hook. Its library default is a
no-op, preserving normal executable behaviour. CONFNIO supplies the hook and,
after CC65 has run destructors and restored BRKV, event, cursor, and display
state, reads the current language ROM with OSBYTE 252 and re-enters it with
OSBYTE 142. This reinitialises the language whose RAM CONFNIO occupied without
hard-coding BASIC.

## Confirmed test results

The focused Beebium tests are in
`integration-tests/beebium/test_config_nio_bbc_real.py`:

- `test_config_nio_bbc_cli_escape_prints_escape` — normal CLI control; passes.
- `test_config_nio_bbc_escape_after_transient_fls_prints_escape` — assembly
  transient control; passes.
- `test_config_nio_bbc_escape_after_cc65_keycode_prints_escape` — minimal
  CC65/C transient; passes, including physical matrix Escape.
- `test_config_nio_bbc_escape_after_exit_returns_cleanly_to_cli[Q]` and `[M]`
  — CONFNIO regressions; pass.

Run from `repos/nio-config`:

```sh
make clean TARGETS=bbc && make TARGETS=bbc
BEEBIUM_HOME=/home/markf/dev/bbc/beebium \
FUJINET_NIO_HOME=/home/markf/dev/nio/fujinet-nio-workspace/repos/fujinet-nio \
./integration-tests/beebium/run_pytest.sh \
  'test_config_nio_bbc_real.py::test_config_nio_bbc_escape_after_exit_returns_cleanly_to_cli[Q]' -q
```

The Beebium wrapper also builds the FujiNet PTY and boot disk. Evidence is
written under `repos/nio-config/test-evidence/`.

## Root-cause evidence

Immediately before launching CONFNIO, the MOS BRK vector is normally:

```text
BRKV = $B402
```

While CONFNIO is active, it is CC65's transient `brkhandler`. After the session
initialisation overrun was fixed, teardown restores:

```text
BRKV = $B402
```

Debugger breakpoints also showed the same hardware stack pointer (`$F8`) on
entry to CONFNIO and on entry to CC65 teardown. The live return-frame bytes
above that stack pointer were unchanged.

Other checks made in the failing test:

- 6502 stack pointer and live return frame are unchanged across CONFNIO.
- IRQs are enabled after return.
- ROMSEL is unchanged.
- EVNTV and MOS Escape-state bytes sampled at `$E5/$E6` are unchanged.
- The minimal CC65 program still works when given CONFNIO's Mode 7 setup.

The remaining `Bad program` response came from overwritten BASIC language RAM,
not any of these machine or MOS states.

## CC65 Escape changes already present

The relevant prior CC65 commit is `b3074286`. It makes Escape available through
`OSRDCH`/`cgetc()` rather than having an asynchronous EVNTV handler consume it.
The minimal CC65 `KEYCODE` control confirms that ordinary CC65 startup and
teardown preserve subsequent CLI Escape handling.

Rebuild CC65's BBC library after changing runtime sources:

```sh
cd repos/cc65/libsrc
make bbc
```

Then clean/rebuild nio-config so its link actually picks up the new library.

## Useful source locations

- `repos/nio-config/src/platform/bbc/config_nio_run.s` — CONFNIO entry,
  keyboard loop, and exit path.
- `repos/cc65/libsrc/bbc/crt0.s`
- `repos/cc65/libsrc/bbc/exit_hook.s`
- `repos/cc65/libsrc/bbc/break_global_install.s` — BRKV install/uninstall.
- `repos/cc65/libsrc/bbc/brk/bbc/break_handler_common.s` — handler state.
- `repos/fujinet-nio-lib/src/platform/bbc/fn_protocol.inc` — assembly session
  count, which must match the C allocation.
- `repos/nio-config/src/platform/bbc/config_nio_exit_hook.s` — CONFNIO's
  language re-entry hook.
- `repos/fn-rom/src/kernel/commands/cmd_run.s` — transient program loader and
  return path.
