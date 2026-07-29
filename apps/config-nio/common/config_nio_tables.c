#define CONFIG_NIO_TABLES_IMPL
#include "config_nio.h"

#include <string.h>

int config_nio_host_get(const config_nio_state_t *state, uint8_t index,
                        char *buf, uint16_t cap)
{
  if (!state || !buf || cap == 0 || index >= CONFIG_NIO_MAX_HOSTS)
    return 0;
  strncpy(buf, state->hosts[index], cap - 1);
  buf[cap - 1] = 0;
  return 1;
}

int config_nio_host_set(config_nio_state_t *state, uint8_t index,
                        const char *value)
{
  if (!state || index >= CONFIG_NIO_MAX_HOSTS)
    return 0;
  strncpy(state->hosts[index], value ? value : "", CONFIG_NIO_URI_MAX);
  state->hosts[index][CONFIG_NIO_URI_MAX] = 0;
  return 1;
}

int config_nio_host_clear(config_nio_state_t *state, uint8_t index)
{
  if (!state || index >= CONFIG_NIO_MAX_HOSTS)
    return 0;
  state->hosts[index][0] = 0;
  return 1;
}

int config_nio_entry_get(const config_nio_state_t *state, uint8_t index,
                         config_nio_entry_t *entry)
{
  if (!state || !entry || index >= CONFIG_NIO_MAX_ENTRIES)
    return 0;
  *entry = state->entries[index];
  return 1;
}

int config_nio_entry_set(config_nio_state_t *state, uint8_t index,
                         const config_nio_entry_t *entry)
{
  if (!state || !entry || index >= CONFIG_NIO_MAX_ENTRIES)
    return 0;
  state->entries[index] = *entry;
  return 1;
}

int config_nio_slot_get(const config_nio_state_t *state, uint8_t index,
                        config_nio_slot_t *slot)
{
  if (!state || !slot || index >= FNCTL_MAX_UNITS)
    return 0;
  *slot = state->slots[index];
  return 1;
}

int config_nio_slot_set(config_nio_state_t *state, uint8_t index,
                        const config_nio_slot_t *slot)
{
  if (!state || !slot || index >= FNCTL_MAX_UNITS)
    return 0;
  state->slots[index] = *slot;
  return 1;
}

int config_nio_mapping_get(const config_nio_state_t *state, uint8_t unit,
                           config_nio_mapping_t *mapping)
{
  if (!state || !mapping || unit >= FNCTL_MAX_UNITS)
    return 0;
  *mapping = state->mappings[unit];
  return 1;
}

int config_nio_mapping_set(config_nio_state_t *state, uint8_t unit,
                           const config_nio_mapping_t *mapping)
{
  if (!state || !mapping || unit >= FNCTL_MAX_UNITS)
    return 0;
  state->mappings[unit] = *mapping;
  return 1;
}

int config_nio_mapping_clear(config_nio_state_t *state, uint8_t unit)
{
  if (!state || unit >= FNCTL_MAX_UNITS)
    return 0;
  memset(&state->mappings[unit], 0, sizeof(state->mappings[unit]));
  return 1;
}
