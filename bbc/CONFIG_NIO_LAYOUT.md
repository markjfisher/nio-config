# BBC config-nio screen layout

`bbc/config_nio_layout.json` is the source of truth for dynamic text positions on the MODE 7 config-nio pages.

The template generator consumes this layout and emits:

- `apps/config-nio/platform/bbc/config_nio_template_data.s`: compressed table data linked into `CONFNIO`.
- `apps/config-nio/platform/bbc/config_nio_layout.h`: C macros used by the BBC UI overlay code.

The source template binaries live in `bbc/assets/config-nio-templates/`:

- `CNHOSTS`
- `CNBROW`
- `CNSLOTS`

Running the generator with no arguments reads those required source files:

```sh
python3 bbc/scripts/generate_config_nio_templates.py
```

Each template must be exactly 1000 bytes, laid out as 40 columns by 25 rows. These files are source assets only; they are not copied to the generated SSDs because `CONFNIO` uses the embedded compressed table.

When moving a pane in the artwork, update the matching coordinates in `bbc/config_nio_layout.json` and rerun the generator. The C UI includes the generated header, so row and field locations move together without editing the BBC C/ASM files for each field.

Avoid using row 24 for fields that are cleared or fully repainted through `OSWRCH`; writing a full line at the bottom of MODE 7 can scroll the display and move the CRTC screen start.
