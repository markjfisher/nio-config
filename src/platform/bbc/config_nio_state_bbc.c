#include "config_nio.h"

#include <bbc.h>
#include <string.h>

void __fastcall__ bbc_oscli(const char *cmd);
void config_nio_bbc_copy_slot_display_uri(char *dst, uint16_t cap,
                                          const char *src);

static char mount_cmd[16];

static int bbc_apply_drive_mapping(uint8_t unit, uint8_t slot)
{
  uint8_t hundreds = 0;
  uint8_t tens = 0;
  while (slot >= 100) { slot = (uint8_t) (slot - 100); hundreds++; }
  while (slot >= 10) { slot = (uint8_t) (slot - 10); tens++; }
  mount_cmd[0] = 'F';
  mount_cmd[1] = 'M';
  mount_cmd[2] = 'O';
  mount_cmd[3] = 'U';
  mount_cmd[4] = 'N';
  mount_cmd[5] = 'T';
  mount_cmd[6] = ' ';
  mount_cmd[7] = (char) ('0' + hundreds);
  mount_cmd[8] = (char) ('0' + tens);
  mount_cmd[9] = (char) ('0' + slot);
  mount_cmd[10] = ' ';
  mount_cmd[11] = (char) ('0' + unit);
  mount_cmd[12] = 13;
  mount_cmd[13] = 0;
  bbc_oscli(mount_cmd);
  return 1;
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
    {
      config_nio_slot_t slot;
      if (!config_nio_read_slot(mapping.slot, &slot) ||
          !slot.enabled || !slot.uri[0]) {
      config_nio_set_status(state, "Mapped slot is empty");
      continue;
      }
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
