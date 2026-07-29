#include "config_nio.h"

#include <bbc.h>
#include <string.h>

void __fastcall__ bbc_oscli(const char *cmd);
void config_nio_bbc_copy_slot_display_uri(char *dst, uint16_t cap,
                                          const char *src);

static fnsvc_mount_t mount_tmp;
static char mount_cmd[16];

static int bbc_apply_drive_mapping(uint8_t unit, uint8_t slot)
{
  mount_cmd[0] = 'F';
  mount_cmd[1] = 'M';
  mount_cmd[2] = 'O';
  mount_cmd[3] = 'U';
  mount_cmd[4] = 'N';
  mount_cmd[5] = 'T';
  mount_cmd[6] = ' ';
  mount_cmd[7] = (char) ('0' + slot);
  mount_cmd[8] = ' ';
  mount_cmd[9] = (char) ('0' + unit);
  mount_cmd[10] = 13;
  mount_cmd[11] = 0;
  bbc_oscli(mount_cmd);
  return 1;
}

int config_nio_refresh_slots(config_nio_state_t *state)
{
  uint8_t slot;
  int ok;

  if (!state)
    return 0;

  ok = 1;
  for (slot = 0; slot < FNCTL_MAX_UNITS; slot++) {
    config_nio_slot_t slot_state;

    memset(&slot_state, 0, sizeof(slot_state));
    if (fnsvc_get_mount(slot, &mount_tmp)) {
      uint16_t n;

      slot_state.enabled = mount_tmp.enabled;
      config_nio_bbc_copy_slot_display_uri(slot_state.uri,
                                           sizeof(slot_state.uri),
                                           mount_tmp.uri);
      n = (uint16_t) strlen(mount_tmp.mode);
      if (n > 3)
        n = 3;
      memcpy(slot_state.mode, mount_tmp.mode, n);
      slot_state.mode[n] = 0;
    } else {
      ok = 0;
    }
    (void) config_nio_slot_set(state, slot, &slot_state);
  }
  return ok;
}

int config_nio_mount_mappings(config_nio_state_t *state)
{
  uint8_t unit;
  uint8_t mounted;

  if (!state)
    return 0;

  mounted = 0;
  for (unit = 0; unit < FNCTL_MAX_UNITS; unit++) {
    config_nio_mapping_t mapping;

    if (!config_nio_mapping_get(state, unit, &mapping))
      continue;
    if (!mapping.valid)
      continue;
    if (mapping.slot >= FNCTL_MAX_UNITS)
      continue;
    if (!fnsvc_get_mount(mapping.slot, &mount_tmp) ||
        !mount_tmp.enabled || !mount_tmp.uri[0]) {
      config_nio_set_status(state, "Mapped slot is empty");
      continue;
    }
    if (!bbc_apply_drive_mapping(unit, mapping.slot)) {
      config_nio_set_status(state, "Drive map failed");
      continue;
    }
    mounted++;
  }

  config_nio_set_status(state, mounted ? "Mounted mappings" : "No mappings mounted");
  return mounted > 0;
}
