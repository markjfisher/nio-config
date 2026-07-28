#include "config_nio.h"

#ifdef CONFIG_NIO_BBC_LITE
#include <bbc.h>
void __fastcall__ bbc_oscli(const char *cmd);
void config_nio_bbc_copy_slot_display_uri(char *dst, uint16_t cap,
                                          const char *src);
#endif
#include <string.h>

static fnsvc_mount_t mount_tmp;

#ifdef CONFIG_NIO_BBC_LITE
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
#endif

#ifndef CONFIG_NIO_BBC_LITE
static int has_scheme_or_prefix(const char *s)
{
  const char *p;

  p = s;
  while (*p && *p != '/' && *p != '\\') {
    if (*p == ':')
      return 1;
    p++;
  }
  return 0;
}

static int append_text(char *out, uint16_t cap, uint16_t *pos, const char *s)
{
  uint16_t len;

  len = (uint16_t) strlen(s);
  if ((uint16_t) (*pos + len) >= cap)
    return 0;
  memcpy(&out[*pos], s, len);
  *pos = (uint16_t) (*pos + len);
  out[*pos] = 0;
  return 1;
}

int config_nio_set_status(config_nio_state_t *state, const char *msg)
{
  uint16_t i;
  uint16_t cap;

  if (!state)
    return 0;
  if (!msg)
    msg = "";
  cap = (uint16_t) sizeof(state->status);
  for (i = 0; (uint16_t) (i + 1) < cap && msg[i]; i++)
    state->status[i] = msg[i];
  state->status[i] = 0;
  return 1;
}
#endif

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
#ifdef CONFIG_NIO_BBC_LITE
      config_nio_bbc_copy_slot_display_uri(slot_state.uri,
                                           sizeof(slot_state.uri),
                                           mount_tmp.uri);
#else
      n = (uint16_t) strlen(mount_tmp.uri);
      if (n >= sizeof(slot_state.uri))
        n = (uint16_t) (sizeof(slot_state.uri) - 1);
      memcpy(slot_state.uri, mount_tmp.uri, n);
      slot_state.uri[n] = 0;
#endif
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

#ifndef CONFIG_NIO_BBC_LITE
int config_nio_compose_uri(const char *host, const char *path,
                           const char *leaf, char *out, uint16_t cap)
{
  uint16_t pos;
  uint16_t host_len;
  int needs_slash;

  if (!host || !*host || !out || cap == 0)
    return 0;

  out[0] = 0;
  pos = 0;

  if (!has_scheme_or_prefix(host)) {
    if (!append_text(out, cap, &pos, "tnfs://"))
      return 0;
  }

  if (!append_text(out, cap, &pos, host))
    return 0;

  host_len = (uint16_t) strlen(host);
  needs_slash = host_len == 0 || host[host_len - 1] != '/';
  if (path && *path) {
    if (needs_slash && !append_text(out, cap, &pos, "/"))
      return 0;
    if (!append_text(out, cap, &pos, path))
      return 0;
  } else if (leaf && *leaf) {
    if (needs_slash && !append_text(out, cap, &pos, "/"))
      return 0;
  } else if (!has_scheme_or_prefix(host) && needs_slash) {
    if (!append_text(out, cap, &pos, "/"))
      return 0;
  }

  if (leaf && *leaf) {
    if (pos > 0 && out[pos - 1] != '/' && !append_text(out, cap, &pos, "/"))
      return 0;
    if (!append_text(out, cap, &pos, leaf))
      return 0;
  }

  return 1;
}
#endif

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
#ifdef CONFIG_NIO_BBC_LITE
    if (!bbc_apply_drive_mapping(unit, mapping.slot)) {
      config_nio_set_status(state, "Drive map failed");
      continue;
    }
#else
    if (!fnsvc_disk_mount(mapping.slot, mount_tmp.uri, mapping.readonly)) {
      config_nio_set_status(state, "Mount failed");
      continue;
    }
    if (!fnctl_set_unit_slot(unit, mapping.slot)) {
      config_nio_set_status(state, "Drive map failed");
      continue;
    }
#endif
    mounted++;
  }

  config_nio_set_status(state, mounted ? "Mounted mappings" : "No mappings mounted");
  return mounted > 0;
}
