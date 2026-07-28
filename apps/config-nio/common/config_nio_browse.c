#include "config_nio.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char uri_buf[FNSVC_MAX_URI + 1];
static char status_buf[48];

static void list_cb(uint8_t is_dir, const char *name, uint32_t size,
                    uint32_t mtime, void *ctx)
{
  config_nio_state_t *state;
  config_nio_entry_t *entry;
  uint16_t n;

  state = (config_nio_state_t *) ctx;
  state->entry_total++;
  if (state->entry_count >= CONFIG_NIO_MAX_ENTRIES) {
    state->entries_truncated = 1;
    return;
  }

  entry = &state->entries[state->entry_count++];
  entry->is_dir = is_dir;
#ifndef CONFIG_NIO_BBC_LITE
  entry->size = size;
  entry->mtime = mtime;
#else
  (void) size;
  (void) mtime;
#endif
  n = (uint16_t) strlen(name);
  if (n > CONFIG_NIO_NAME_MAX)
    n = CONFIG_NIO_NAME_MAX;
  memcpy(entry->name, name, n);
  entry->name[n] = 0;
}

static int refresh_entries(config_nio_state_t *state, uint8_t host)
{
  state->entry_count = 0;
  state->entry_total = 0;
  state->entries_truncated = 0;

  if (!config_nio_compose_uri(state->hosts[host], state->browse_path, "",
                              uri_buf, sizeof(uri_buf))) {
    config_nio_set_status(state, "Path is too long");
    return 0;
  }

  if (!fnsvc_list_directory(uri_buf, list_cb, state)) {
    sprintf(status_buf, "Browse failed: error %u status %u",
            (unsigned) fnsvc_last_error(),
            (unsigned) fnsvc_last_status());
    config_nio_set_status(state, status_buf);
    return 0;
  }

  config_nio_set_status(state, state->entries_truncated ? "Entries loaded (more)" : "Entries loaded");
  return 1;
}

static void parent_path(char *path)
{
  uint16_t len;

  len = (uint16_t) strlen(path);
  while (len > 0 && path[len - 1] == '/')
    path[--len] = 0;
  while (len > 0 && path[len - 1] != '/')
    path[--len] = 0;
}

static int enter_dir(config_nio_state_t *state, const char *name)
{
  uint16_t len;
  uint16_t nlen;

  len = (uint16_t) strlen(state->browse_path);
  nlen = (uint16_t) strlen(name);
  if ((uint16_t) (len + nlen + 2) > CONFIG_NIO_PATH_MAX) {
    config_nio_set_status(state, "Path is too long");
    return 0;
  }
  if (len > 0 && state->browse_path[len - 1] != '/')
    state->browse_path[len++] = '/';
  memcpy(&state->browse_path[len], name, nlen);
  len = (uint16_t) (len + nlen);
  state->browse_path[len++] = '/';
  state->browse_path[len] = 0;
  return 1;
}

static int prompt_index(const char *label, uint8_t max, uint8_t *out)
{
  char input[8];
  int v;

  if (!config_nio_ui_prompt(label, input, sizeof(input)))
    return 0;
  if (!input[0])
    return 0;
  v = atoi(input);
  if (v < 0 || v >= max)
    return 0;
  *out = (uint8_t) v;
  return 1;
}

int config_nio_browse(config_nio_state_t *state, uint8_t host)
{
  uint8_t selected;

  if (!state || host >= state->host_count)
    return 0;

  state->browse_path[0] = 0;
  selected = 0;
  if (!refresh_entries(state, host))
    return 0;

  for (;;) {
    uint8_t i;
    int key;

    config_nio_ui_clear();
    config_nio_ui_header("Browse", "W/S Move  E Enter  A Assign  U Up  R Reload  Q Back");
    config_nio_ui_print(state->hosts[host]);
    config_nio_ui_print("/");
    config_nio_ui_println(state->browse_path);
    config_nio_ui_println("");

    for (i = 0; i < state->entry_count; i++) {
      config_nio_entry_t *entry;

      entry = &state->entries[i];
      config_nio_ui_putc(i == selected ? '>' : ' ');
      config_nio_ui_print_uint((unsigned) i);
      config_nio_ui_print(" ");
      config_nio_ui_print((entry->is_dir & CONFIG_NIO_ENTRY_FLAG_DIR) ? "D " : "F ");
      config_nio_ui_print_padded(entry->name, 24);
      config_nio_ui_print(" ");
      config_nio_ui_print_ulong((unsigned long) entry->size);
      config_nio_ui_println("");
    }
    config_nio_ui_status(state->status);

    key = config_nio_ui_get_key();
    if (key == 'q' || key == 'Q')
      return 1;
    if ((key == 'w' || key == 'W') && selected > 0)
      selected--;
    else if ((key == 's' || key == 'S') &&
             selected + 1 < state->entry_count)
      selected++;
    else if (key == 'u' || key == 'U') {
      parent_path(state->browse_path);
      selected = 0;
      (void) refresh_entries(state, host);
    } else if (key == 'r' || key == 'R') {
      selected = 0;
      (void) refresh_entries(state, host);
    } else if ((key == 'e' || key == 'E' || key == '\r' || key == '\n') &&
               state->entry_count > 0) {
      if (state->entries[selected].is_dir & CONFIG_NIO_ENTRY_FLAG_NAME_TRUNCATED) {
        config_nio_set_status(state, "Name too long for this client");
      } else if (state->entries[selected].is_dir & CONFIG_NIO_ENTRY_FLAG_DIR) {
        if (enter_dir(state, state->entries[selected].name)) {
          selected = 0;
          (void) refresh_entries(state, host);
        }
      } else {
        config_nio_set_status(state, "Use A to assign files to a slot");
      }
    } else if ((key == 'a' || key == 'A') && state->entry_count > 0) {
      uint8_t slot;
      if (state->entries[selected].is_dir & CONFIG_NIO_ENTRY_FLAG_NAME_TRUNCATED) {
        config_nio_set_status(state, "Name too long for this client");
        continue;
      }
      if (state->entries[selected].is_dir & CONFIG_NIO_ENTRY_FLAG_DIR) {
        config_nio_set_status(state, "Pick a file, not a directory");
        continue;
      }
      if (!prompt_index("Assign to slot", FNCTL_MAX_UNITS, &slot)) {
        config_nio_set_status(state, "Bad slot");
        continue;
      }
      if (!config_nio_compose_uri(state->hosts[host], state->browse_path,
                                  state->entries[selected].name,
                                  uri_buf, sizeof(uri_buf))) {
        config_nio_set_status(state, "URI is too long");
        continue;
      }
      if (!fnsvc_set_mount(slot, uri_buf, "rw", 1)) {
        config_nio_set_status(state, "Unable to save slot");
        continue;
      }
      (void) config_nio_refresh_slots(state);
      config_nio_set_status(state, "Assigned file to slot");
    }
  }
}
