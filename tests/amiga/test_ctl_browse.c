#include "check.h"
#include "fake_nio.h"
#include "amiga_ctl.h"

static config_nio_state_t state;
static amiga_ctl_t ctl;
static char many_names[250][8];
static fake_dir_entry_t many[250];

static int no_exec(const char *command, char *output, uint16_t cap,
                   void *ctx)
{
  (void) command;
  (void) output;
  (void) cap;
  (void) ctx;
  return 20;
}

void test_ctl_browse(void)
{
  static const fake_dir_entry_t root[] = {
    { CONFIG_NIO_ENTRY_FLAG_DIR, "GAMES", 0, 0 },
    { 0, "boot.adf", 901120, 1735689600UL },
    { CONFIG_NIO_ENTRY_FLAG_NAME_TRUNCATED, "very_long_na", 1, 1 },
  };
  static const fake_dir_entry_t games[] = { { 0, "a.adf", 880, 0 } };
  char uri[CONFIG_NIO_URI_MAX + 1];
  unsigned i;

  CHECK(CONFIG_NIO_MAX_ENTRIES == 200);
  fake_nio_reset();
  fake_dir_put("tnfs://fujinet.online/", root, 3);
  fake_dir_put("tnfs://fujinet.online/GAMES/", games, 1);
  fake_dir_fail("tnfs://fujinet.diller.org/");
  CHECK(config_nio_load(&state));
  amiga_ctl_init(&ctl, &state, 0, 10, no_exec, NULL);

  amiga_list_select(&ctl.hosts, 2);
  CHECK(amiga_ctl_browse_open(&ctl));
  CHECK(ctl.page == AMIGA_PAGE_BROWSE && ctl.browse_open);
  CHECK(ctl.entries.count == 3 && ctl.entries.selected == 0);
  CHECK_STR(state.status, "Entries loaded");

  CHECK(amiga_ctl_browse_select_name(&ctl, "boot.adf"));
  CHECK(amiga_ctl_browse_uri(&ctl, uri, sizeof(uri)));
  CHECK_STR(uri, "tnfs://fujinet.online/boot.adf");
  CHECK(!amiga_ctl_browse_activate(&ctl));
  CHECK_STR(state.status, "Press Mount... to mount this image");
  CHECK(amiga_ctl_browse_assign(&ctl, 12, 1));
  CHECK_STR(fake_slot_uri(12), "tnfs://fujinet.online/boot.adf");
  CHECK(fake_slot_readonly(12) == 1);
  CHECK_STR(state.status, "Assigned to slot 12");

  CHECK(amiga_ctl_browse_select_name(&ctl, "very_long_na"));
  CHECK(!amiga_ctl_browse_activate(&ctl));
  CHECK_STR(state.status, "Name too long for this client");
  CHECK(!amiga_ctl_browse_assign(&ctl, 13, 0));
  CHECK(fake_slot_uri(13) == NULL);

  CHECK(amiga_ctl_browse_select_name(&ctl, "GAMES"));
  CHECK(!amiga_ctl_browse_assign(&ctl, 13, 0));
  CHECK_STR(state.status, "Pick a file, not a drawer");
  CHECK(amiga_ctl_browse_activate(&ctl));
  CHECK_STR(state.browse_path, "GAMES/");
  /* Inside a drawer the first row is "..", the parent, like cd .. */
  CHECK(ctl.entries.count == 2 && ctl.entries.selected == 0);
  CHECK(amiga_ctl_browse_row_is_parent(&ctl, 0));
  CHECK(!amiga_ctl_browse_row_is_parent(&ctl, 1));
  CHECK(amiga_ctl_browse_row_entry(&ctl, 0) == NULL);
  CHECK_STR(amiga_ctl_browse_row_entry(&ctl, 1)->name, "a.adf");
  CHECK(amiga_ctl_browse_row_entry(&ctl, 2) == NULL);
  CHECK(!amiga_ctl_browse_uri(&ctl, uri, sizeof(uri)));
  CHECK_STR(state.status, "Pick a file, not a drawer");
  CHECK(amiga_ctl_browse_select_name(&ctl, "a.adf"));
  CHECK(ctl.entries.selected == 1);
  CHECK(amiga_ctl_browse_uri(&ctl, uri, sizeof(uri)));
  CHECK_STR(uri, "tnfs://fujinet.online/GAMES/a.adf");
  CHECK(amiga_ctl_browse_select_name(&ctl, ".."));
  CHECK(ctl.entries.selected == 0);
  CHECK(amiga_ctl_browse_activate(&ctl));           /* double-click ".." */
  CHECK_STR(state.browse_path, "");
  /* At the host's top there is no "..". */
  CHECK(ctl.entries.count == 3);
  CHECK(!amiga_ctl_browse_row_is_parent(&ctl, 0));
  CHECK_STR(amiga_ctl_browse_row_entry(&ctl, 0)->name, "GAMES");
  CHECK(!amiga_ctl_browse_select_name(&ctl, ".."));
  CHECK(amiga_ctl_browse_select_name(&ctl, "GAMES"));
  CHECK(amiga_ctl_browse_activate(&ctl));
  CHECK(amiga_ctl_browse_parent(&ctl));
  CHECK_STR(state.browse_path, "");
  CHECK(ctl.entries.count == 3);
  CHECK(!amiga_ctl_browse_parent(&ctl));
  CHECK(!amiga_ctl_browse_select_name(&ctl, "nope"));

  /* Unreachable host: page stays usable, nothing selectable. */
  amiga_list_select(&ctl.hosts, 1);
  CHECK(!amiga_ctl_browse_open(&ctl));
  CHECK(ctl.page == AMIGA_PAGE_BROWSE);
  CHECK(ctl.entries.count == 0);
  CHECK(!strncmp(state.status, "Browse failed: error ", 21));
  CHECK(!amiga_ctl_browse_activate(&ctl));
  CHECK_STR(state.status, "Nothing selected");

  /* Directory larger than the table. */
  for (i = 0; i < 250; i++) {
    sprintf(many_names[i], "F%03u", i);
    many[i].is_dir = 0;
    many[i].name = many_names[i];
    many[i].size = i;
    many[i].mtime = 0;
  }
  fake_dir_put("sd0:/", many, 250);
  amiga_list_select(&ctl.hosts, 0);
  CHECK(amiga_ctl_browse_open(&ctl));
  /* ListPages: every entry is reachable, in windows loaded on demand. */
  CHECK(ctl.entries.count == 250);
  CHECK_STR(state.status, "Entries loaded");
  CHECK(state.entry_count <= 200 && state.entry_total == 250);
  CHECK_STR(amiga_ctl_browse_row_entry(&ctl, 0)->name, "F000");
  CHECK_STR(amiga_ctl_browse_row_entry(&ctl, 249)->name, "F249");
  CHECK(ctl.browse_base > 0);
  CHECK_STR(amiga_ctl_browse_row_entry(&ctl, 3)->name, "F003");
  CHECK(amiga_ctl_browse_row_entry(&ctl, 250) == NULL);
  CHECK(amiga_ctl_browse_select_name(&ctl, "F249"));
  CHECK(ctl.entries.selected == 249);
  CHECK(amiga_ctl_browse_select_name(&ctl, "F001"));
  CHECK(ctl.entries.selected == 1);

  /* Failure after part of a new window must not relabel it with the old base. */
  CHECK(amiga_ctl_browse_refresh(&ctl));
  fake_dir_pages_fail_at(188); /* row 249 centres at 148, next reply at 188 */
  CHECK(amiga_ctl_browse_row_entry(&ctl, 249) == NULL);
  CHECK(state.entry_count == 0);
  CHECK(!strncmp(state.status, "Browse failed:", 14));
  fake_dir_pages_fail_at(0xFFFFFFFFUL);
  {
    unsigned calls = fake_dir_pages_calls();
    CHECK(amiga_ctl_browse_row_entry(&ctl, 0) == NULL);
    CHECK(!amiga_ctl_browse_select_name(&ctl, "F000"));
    CHECK(fake_dir_pages_calls() == calls); /* repaint does not retry repeatedly */
  }
  CHECK(amiga_ctl_browse_refresh(&ctl));
  CHECK_STR(amiga_ctl_browse_row_entry(&ctl, 0)->name, "F000");
  CHECK_STR(amiga_ctl_browse_row_entry(&ctl, 249)->name, "F249");

  /* Only an explicit Refresh asks the device to read the folder again. */
  {
    unsigned before = fake_dir_pages_refreshes();

    CHECK(amiga_ctl_browse_refresh(&ctl));
    CHECK(fake_dir_pages_refreshes() == before);
    CHECK(amiga_ctl_browse_reread(&ctl));
    CHECK(fake_dir_pages_refreshes() == before + 1);
    CHECK(amiga_ctl_browse_refresh(&ctl));
    CHECK(fake_dir_pages_refreshes() == before + 1);
  }

  /* Firmware without ListPages: the whole folder through the old command,
   * showing only what fits the table. */
  fake_dir_pages_unsupported(1);
  CHECK(amiga_ctl_browse_open(&ctl));
  CHECK(!ctl.browse_paged);
  CHECK(ctl.entries.count == 200);
  CHECK_STR(state.status, "Showing 200 of 250 entries");
  CHECK_STR(amiga_ctl_browse_row_entry(&ctl, 199)->name, "F199");
  CHECK(amiga_ctl_browse_row_entry(&ctl, 200) == NULL);
  fake_dir_pages_unsupported(0);
  CHECK(amiga_ctl_browse_open(&ctl));
  CHECK(ctl.browse_paged && ctl.entries.count == 250);

  /* Full names up to 220 bytes survive; firmware-truncated names are unsafe. */
  {
    char name80[85], name220[221], cut_name[221], overlong[222], prefix[221];
    fake_dir_entry_t entries[4];
    memset(name80, 'a', 80); strcpy(name80 + 80, ".adf");
    memset(name220, 'b', 216); strcpy(name220 + 216, ".adf");
    memset(cut_name, 'c', 220); cut_name[220] = 0;
    memset(overlong, 'd', 221); overlong[221] = 0;
    memset(prefix, 'd', 220); prefix[220] = 0;
    entries[0] = (fake_dir_entry_t) {0, name80, 1, 0};
    entries[1] = (fake_dir_entry_t) {0, name220, 1, 0};
    entries[2] = (fake_dir_entry_t) {CONFIG_NIO_ENTRY_FLAG_NAME_TRUNCATED, cut_name, 1, 0};
    entries[3] = (fake_dir_entry_t) {0, overlong, 1, 0};
    fake_dir_put("sd0:/", entries, 4);
    amiga_list_select(&ctl.hosts, 0);
    CHECK(amiga_ctl_browse_open(&ctl));
    CHECK(amiga_ctl_browse_select_name(&ctl, name80));
    CHECK(amiga_ctl_browse_uri(&ctl, uri, sizeof(uri)));
    CHECK(strlen(uri) == strlen("sd0:/") + strlen(name80));
    CHECK(amiga_ctl_browse_select_name(&ctl, name220));
    CHECK(amiga_ctl_browse_uri(&ctl, uri, sizeof(uri)));
    CHECK(strlen(uri) == strlen("sd0:/") + 220);
    CHECK(amiga_ctl_browse_select_name(&ctl, cut_name));
    CHECK(!amiga_ctl_browse_uri(&ctl, uri, sizeof(uri)));
    CHECK_STR(state.status, "Name too long for this client");
    CHECK(amiga_ctl_browse_select_name(&ctl, prefix));
    CHECK(!amiga_ctl_browse_uri(&ctl, uri, sizeof(uri))); /* local cut is flagged too */
    /* The older ListDirectory fallback must preserve the same cut flag. */
    fake_dir_pages_unsupported(1);
    CHECK(amiga_ctl_browse_open(&ctl));
    CHECK(amiga_ctl_browse_select_name(&ctl, name220));
    CHECK(amiga_ctl_browse_uri(&ctl, uri, sizeof(uri)));
    CHECK(amiga_ctl_browse_select_name(&ctl, cut_name));
    CHECK(!amiga_ctl_browse_uri(&ctl, uri, sizeof(uri)));
    fake_dir_pages_unsupported(0);
  }

  /* Reserve room for the parent row at the 16-bit list limit. */
  {
    static const fake_dir_entry_t empty[] = {{0, "unused", 0, 0}};
    fake_dir_put("sd0:/", empty, 0);
    fake_dir_put("sd0:/huge/", empty, 0);
    amiga_list_select(&ctl.hosts, 0);
    fake_dir_pages_total(65535UL);
    CHECK(amiga_ctl_browse_open(&ctl));
    CHECK(state.entry_total == 65535 && ctl.entries.count == 65535);
    CHECK_STR(state.status, "Entries loaded");
    fake_dir_pages_total(65536UL);
    CHECK(amiga_ctl_browse_refresh(&ctl));
    CHECK(state.entry_total == 65535 && ctl.entries.count == 65535);
    CHECK_STR(state.status, "Showing the first 65535 entries");
    strcpy(state.browse_path, "huge/");
    ctl.browse_host = 0;
    fake_dir_pages_total(65535UL);
    CHECK(amiga_ctl_browse_refresh(&ctl));
    CHECK(state.entry_total == 65534 && ctl.entries.count == 65535);
    CHECK(amiga_ctl_browse_row_is_parent(&ctl, 0));
    CHECK_STR(state.status, "Showing the first 65534 entries");
    /* A last window may include rows past the displayed limit; searching
     * for one must not wrap its index into an unrelated visible row. */
    ctl.browse_base = 65532;
    state.entry_count = 3;
    strcpy(state.entries[0].name, "last-2");
    strcpy(state.entries[1].name, "last-1");
    strcpy(state.entries[2].name, "beyond");
    amiga_list_select(&ctl.entries, 0);
    fake_dir_pages_fail_at(0);
    CHECK(!amiga_ctl_browse_select_name(&ctl, "beyond"));
    CHECK(ctl.entries.selected == 0);
    fake_dir_pages_fail_at(0xFFFFFFFFUL);
    fake_dir_pages_total(0);
  }

  /* No host at all. */
  while (state.host_count)
    CHECK(amiga_ctl_host_remove(&ctl));
  CHECK(!amiga_ctl_browse_open(&ctl));
  CHECK_STR(state.status, "No host selected");
}
