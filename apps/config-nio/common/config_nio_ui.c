#include "config_nio.h"

#include <stdlib.h>
#include <string.h>

static char index_input[8];
static char uri_edit[CONFIG_NIO_URI_MAX + 1];
static char uri_tmp[CONFIG_NIO_URI_MAX + 1];
static char mode_edit[4];
static char drive_label[16];
static config_nio_slot_t slot_tmp_a;
static config_nio_slot_t slot_tmp_b;

static int prompt_index(const char *label, uint8_t max, uint8_t *out)
{
  int value;

  if (!config_nio_ui_prompt(label, index_input, sizeof(index_input)))
    return 0;
  if (!index_input[0])
    return 0;
  value = atoi(index_input);
  if (value < 0 || value >= max)
    return 0;
  *out = (uint8_t) value;
  return 1;
}

static void show_hosts(config_nio_state_t *state)
{
  for (;;) {
    uint8_t i;
    int key;

    config_nio_ui_clear();
    config_nio_ui_header("Hosts", "A Add  E Edit  D Delete  W/S Move  B Browse  Q Back");
    for (i = 0; i < state->host_count; i++) {
      config_nio_ui_print_uint((unsigned) i);
      config_nio_ui_print("  ");
      config_nio_ui_println(state->hosts[i]);
    }
    if (state->host_count == 0)
      config_nio_ui_println("No hosts");
    config_nio_ui_status(state->status);

    key = config_nio_ui_get_key();
    if (key == 'q' || key == 'Q')
      return;
    if (key == 'a' || key == 'A') {
      if (state->host_count >= CONFIG_NIO_MAX_HOSTS) {
        config_nio_set_status(state, "Host list is full");
      } else if (config_nio_ui_prompt("Host", state->hosts[state->host_count],
                                      CONFIG_NIO_URI_MAX + 1) &&
                 state->hosts[state->host_count][0]) {
        state->host_count++;
        (void) config_nio_save_hosts(state);
        config_nio_set_status(state, "Host added");
      }
    } else if (key == 'e' || key == 'E') {
      uint8_t idx;
      if (prompt_index("Host number", state->host_count, &idx)) {
        strcpy(uri_edit, state->hosts[idx]);
        if (config_nio_ui_prompt("New host", uri_edit, sizeof(uri_edit)) &&
            uri_edit[0]) {
          strcpy(state->hosts[idx], uri_edit);
          (void) config_nio_save_hosts(state);
          config_nio_set_status(state, "Host updated");
        }
      }
    } else if (key == 'd' || key == 'D') {
      uint8_t idx;
      if (prompt_index("Delete host", state->host_count, &idx)) {
        for (i = idx; i + 1 < state->host_count; i++)
          strcpy(state->hosts[i], state->hosts[i + 1]);
        state->host_count--;
        (void) config_nio_save_hosts(state);
        config_nio_set_status(state, "Host deleted");
      }
    } else if (key == 'w' || key == 'W' || key == 's' || key == 'S') {
      uint8_t idx;
      if (prompt_index("Move host", state->host_count, &idx)) {
        uint8_t to;
        if ((key == 'w' || key == 'W') && idx == 0)
          continue;
        if ((key == 's' || key == 'S') && idx + 1 >= state->host_count)
          continue;
        to = (uint8_t) ((key == 'w' || key == 'W') ? idx - 1 : idx + 1);
        strcpy(uri_tmp, state->hosts[idx]);
        strcpy(state->hosts[idx], state->hosts[to]);
        strcpy(state->hosts[to], uri_tmp);
        (void) config_nio_save_hosts(state);
        config_nio_set_status(state, "Host moved");
      }
    } else if (key == 'b' || key == 'B') {
      uint8_t idx;
      if (prompt_index("Browse host", state->host_count, &idx))
        (void) config_nio_browse(state, idx);
    }
  }
}

static void show_slots(config_nio_state_t *state)
{
  for (;;) {
    uint8_t i;
    int key;

    (void) config_nio_refresh_slots(state);
    config_nio_ui_clear();
    config_nio_ui_header("Slots", "E Edit URI  D Delete  S Swap  Q Back");
    for (i = 0; i < FNCTL_MAX_UNITS; i++) {
      config_nio_slot_t *mount;
      mount = &state->slots[i];
      config_nio_ui_print_uint((unsigned) i);
      config_nio_ui_print("  ");
      config_nio_ui_println(mount->enabled && mount->uri[0] ? mount->uri : "(empty)");
    }
    config_nio_ui_status(state->status);

    key = config_nio_ui_get_key();
    if (key == 'q' || key == 'Q')
      return;
    if (key == 'd' || key == 'D') {
      uint8_t slot;
      if (prompt_index("Delete slot", FNCTL_MAX_UNITS, &slot)) {
        if (fnsvc_set_mount(slot, "", "r", 0)) {
          (void) config_nio_refresh_slots(state);
          config_nio_set_status(state, "Slot cleared");
        } else {
          config_nio_set_status(state, "Unable to clear slot");
        }
      }
    } else if (key == 'e' || key == 'E') {
      uint8_t slot;
      if (prompt_index("Slot", FNCTL_MAX_UNITS, &slot)) {
        strcpy(uri_edit, state->slots[slot].uri);
        if (config_nio_ui_prompt("URI", uri_edit, sizeof(uri_edit)) &&
            uri_edit[0]) {
          if (fnsvc_set_mount(slot, uri_edit, "rw", 1)) {
            (void) config_nio_refresh_slots(state);
            config_nio_set_status(state, "Slot saved");
          } else {
            config_nio_set_status(state, "Unable to save slot");
          }
        }
      }
    } else if (key == 's' || key == 'S') {
      uint8_t a;
      uint8_t b;
      if (prompt_index("First slot", FNCTL_MAX_UNITS, &a) &&
          prompt_index("Second slot", FNCTL_MAX_UNITS, &b)) {
        slot_tmp_a = state->slots[a];
        slot_tmp_b = state->slots[b];
        if (fnsvc_set_mount(a, slot_tmp_b.uri,
                            slot_tmp_b.mode[0] ? slot_tmp_b.mode : "r",
                            slot_tmp_b.enabled) &&
            fnsvc_set_mount(b, slot_tmp_a.uri,
                            slot_tmp_a.mode[0] ? slot_tmp_a.mode : "r",
                            slot_tmp_a.enabled)) {
          (void) config_nio_refresh_slots(state);
          config_nio_set_status(state, "Slots swapped");
        } else {
          config_nio_set_status(state, "Swap failed");
        }
      }
    }
  }
}

static void show_mappings(config_nio_state_t *state)
{
  if (config_nio_ui_show_mappings(state))
    return;

  for (;;) {
    uint8_t unit;
    int key;

    config_nio_ui_clear();
    config_nio_ui_header("Drive Map", "E Edit  C Clear  Q Back");
    for (unit = 0; unit < FNCTL_MAX_UNITS; unit++) {
      config_nio_ui_drive_label(unit, drive_label, sizeof(drive_label));
      if (state->mappings[unit].valid) {
        config_nio_ui_print_uint((unsigned) unit);
        config_nio_ui_print("  ");
        config_nio_ui_print_padded(drive_label, 8);
        config_nio_ui_print(" slot ");
        config_nio_ui_print_uint((unsigned) state->mappings[unit].slot);
        config_nio_ui_print(" ");
        config_nio_ui_println(state->mappings[unit].readonly ? "ro" : "rw");
      } else {
        config_nio_ui_print_uint((unsigned) unit);
        config_nio_ui_print("  ");
        config_nio_ui_print_padded(drive_label, 8);
        config_nio_ui_println(" (not mapped)");
      }
    }
    config_nio_ui_status(state->status);

    key = config_nio_ui_get_key();
    if (key == 'q' || key == 'Q')
      return;
    if (key == 'e' || key == 'E') {
      uint8_t unit_idx;
      uint8_t slot;
      if (prompt_index("Drive/unit", FNCTL_MAX_UNITS, &unit_idx) &&
          prompt_index("Slot", FNCTL_MAX_UNITS, &slot)) {
        strcpy(mode_edit, state->mappings[unit_idx].readonly ? "ro" : "rw");
        (void) config_nio_ui_prompt("Mode ro/rw", mode_edit, sizeof(mode_edit));
        state->mappings[unit_idx].valid = 1;
        state->mappings[unit_idx].slot = slot;
        state->mappings[unit_idx].readonly =
          (uint8_t) (strcmp(mode_edit, "ro") == 0 || strcmp(mode_edit, "RO") == 0);
        (void) config_nio_save_mappings(state);
        config_nio_set_status(state, "Mapping saved");
      }
    } else if (key == 'c' || key == 'C') {
      uint8_t unit_idx;
      if (prompt_index("Clear drive/unit", FNCTL_MAX_UNITS, &unit_idx)) {
        memset(&state->mappings[unit_idx], 0, sizeof(state->mappings[unit_idx]));
        (void) config_nio_save_mappings(state);
        config_nio_set_status(state, "Mapping cleared");
      }
    }
  }
}

void config_nio_run(config_nio_state_t *state)
{
  int done;

  if (config_nio_ui_run(state))
    return;

  done = 0;
  while (!done) {
    uint8_t i;
    int key;

    (void) config_nio_refresh_slots(state);
    config_nio_ui_clear();
    config_nio_ui_header("config-nio", "H Hosts  B Browse  S Slots  M Map  X Mount+Exit  Q Quit");
    config_nio_ui_println("Hosts");
    for (i = 0; i < state->host_count && i < 3; i++)
      config_nio_ui_println(state->hosts[i]);
    if (state->host_count > 3) {
      config_nio_ui_print("... ");
      config_nio_ui_print_uint((unsigned) state->host_count);
      config_nio_ui_println(" total");
    }
    config_nio_ui_println("");
    config_nio_ui_println("Mappings");
    for (i = 0; i < FNCTL_MAX_UNITS; i++) {
      if (!state->mappings[i].valid)
        continue;
      config_nio_ui_drive_label(i, drive_label, sizeof(drive_label));
      config_nio_ui_print_padded(drive_label, 8);
      config_nio_ui_print(" -> slot ");
      config_nio_ui_print_uint((unsigned) state->mappings[i].slot);
      config_nio_ui_print(" ");
      config_nio_ui_println(state->mappings[i].readonly ? "ro" : "rw");
    }
    config_nio_ui_status(state->status);

    key = config_nio_ui_get_key();
    if (key == 'q' || key == 'Q') {
      done = 1;
    } else if (key == 'h' || key == 'H') {
      show_hosts(state);
    } else if (key == 'b' || key == 'B') {
      uint8_t idx;
      if (prompt_index("Browse host", state->host_count, &idx))
        (void) config_nio_browse(state, idx);
    } else if (key == 's' || key == 'S') {
      show_slots(state);
    } else if (key == 'm' || key == 'M') {
      show_mappings(state);
    } else if (key == 'x' || key == 'X') {
      (void) config_nio_mount_mappings(state);
      config_nio_ui_clear();
      config_nio_ui_header("Mount", "Press a key to exit");
      config_nio_ui_status(state->status);
      config_nio_ui_pause();
      done = 1;
    }
  }
}
