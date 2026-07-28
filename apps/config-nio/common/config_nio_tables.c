#define CONFIG_NIO_TABLES_IMPL
#include "config_nio.h"

#include <string.h>

#ifdef CONFIG_NIO_BBC_LITE
void config_nio_xram_read(uint16_t offset, void *dst, uint16_t len);
void config_nio_xram_write(uint16_t offset, const void *src, uint16_t len);

#define XRAM_HOSTS_OFF 0
#define XRAM_HOST_SIZE (CONFIG_NIO_URI_MAX + 1)
#define XRAM_SLOTS_OFF (XRAM_HOSTS_OFF + (CONFIG_NIO_MAX_HOSTS * XRAM_HOST_SIZE))
#define XRAM_SLOT_SIZE ((uint16_t) sizeof(config_nio_slot_t))
#define XRAM_MAPPINGS_OFF (XRAM_SLOTS_OFF + (FNCTL_MAX_UNITS * XRAM_SLOT_SIZE))
#define XRAM_MAPPING_SIZE ((uint16_t) sizeof(config_nio_mapping_t))
#define XRAM_ENTRIES_OFF (XRAM_MAPPINGS_OFF + (FNCTL_MAX_UNITS * XRAM_MAPPING_SIZE))
#define XRAM_ENTRY_SIZE ((uint16_t) sizeof(config_nio_entry_t))

static uint16_t host_off(uint8_t index)
{
  return (uint16_t) (XRAM_HOSTS_OFF + ((uint16_t) index * XRAM_HOST_SIZE));
}

static uint16_t slot_off(uint8_t index)
{
  return (uint16_t) (XRAM_SLOTS_OFF + ((uint16_t) index * XRAM_SLOT_SIZE));
}

static uint16_t mapping_off(uint8_t unit)
{
  return (uint16_t) (XRAM_MAPPINGS_OFF + ((uint16_t) unit * XRAM_MAPPING_SIZE));
}

static uint16_t entry_off(uint8_t index)
{
  return (uint16_t) (XRAM_ENTRIES_OFF + ((uint16_t) index * XRAM_ENTRY_SIZE));
}

static int write_string(uint16_t offset, uint16_t record_size, const char *value)
{
  uint16_t len;
  char zero;

  if (!value)
    value = "";
  len = (uint16_t) strlen(value);
  if (len >= record_size)
    len = (uint16_t) (record_size - 1);
  if (len)
    config_nio_xram_write(offset, value, len);
  zero = 0;
  config_nio_xram_write((uint16_t) (offset + len), &zero, 1);
  return 1;
}

int config_nio_bbc_host_get(uint8_t index, char *buf, uint16_t cap)
{
  if (!buf || cap == 0)
    return 0;
  buf[0] = 0;
  if (index >= CONFIG_NIO_MAX_HOSTS)
    return 0;
  if (cap > XRAM_HOST_SIZE)
    cap = XRAM_HOST_SIZE;
  config_nio_xram_read(host_off(index), buf, (uint16_t) (cap - 1));
  buf[cap - 1] = 0;
  return 1;
}

int config_nio_bbc_host_set(uint8_t index, const char *value)
{
  if (index >= CONFIG_NIO_MAX_HOSTS)
    return 0;
  return write_string(host_off(index), XRAM_HOST_SIZE, value);
}

int config_nio_bbc_host_clear(uint8_t index)
{
  return config_nio_bbc_host_set(index, "");
}

int config_nio_bbc_entry_get(uint8_t index, config_nio_entry_t *entry)
{
  if (!entry || index >= CONFIG_NIO_MAX_ENTRIES)
    return 0;
  config_nio_xram_read(entry_off(index), entry, sizeof(*entry));
  return 1;
}

int config_nio_bbc_entry_set(uint8_t index, const config_nio_entry_t *entry)
{
  if (!entry || index >= CONFIG_NIO_MAX_ENTRIES)
    return 0;
  config_nio_xram_write(entry_off(index), entry, sizeof(*entry));
  return 1;
}

int config_nio_bbc_slot_get(uint8_t index, config_nio_slot_t *slot)
{
  if (!slot || index >= FNCTL_MAX_UNITS)
    return 0;
  config_nio_xram_read(slot_off(index), slot, sizeof(*slot));
  return 1;
}

int config_nio_bbc_slot_set(uint8_t index, const config_nio_slot_t *slot)
{
  if (!slot || index >= FNCTL_MAX_UNITS)
    return 0;
  config_nio_xram_write(slot_off(index), slot, sizeof(*slot));
  return 1;
}

int config_nio_bbc_mapping_get(uint8_t unit, config_nio_mapping_t *mapping)
{
  if (!mapping || unit >= FNCTL_MAX_UNITS)
    return 0;
  config_nio_xram_read(mapping_off(unit), mapping, sizeof(*mapping));
  return 1;
}

int config_nio_bbc_mapping_set(uint8_t unit, const config_nio_mapping_t *mapping)
{
  if (!mapping || unit >= FNCTL_MAX_UNITS)
    return 0;
  config_nio_xram_write(mapping_off(unit), mapping, sizeof(*mapping));
  return 1;
}

int config_nio_bbc_mapping_clear(uint8_t unit)
{
  config_nio_mapping_t mapping;

  memset(&mapping, 0, sizeof(mapping));
  return config_nio_bbc_mapping_set(unit, &mapping);
}
#else
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
#endif
