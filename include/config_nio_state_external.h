#ifndef CONFIG_NIO_STATE_EXTERNAL_H
#define CONFIG_NIO_STATE_EXTERNAL_H

#define CONFIG_NIO_COLOR_COUNT 0
#define CONFIG_NIO_MAX_HOSTS 16
#define CONFIG_NIO_MAX_ENTRIES 12
#define CONFIG_NIO_URI_MAX 128
#define CONFIG_NIO_NAME_MAX 30
#define CONFIG_NIO_TEXT_MAX 768
#define CONFIG_NIO_PATH_MAX 160
#define CONFIG_NIO_STATUS_MAX 0

typedef struct {
  uint8_t valid;
  uint8_t slot;
  uint8_t readonly;
} config_nio_mapping_t;

typedef struct {
  uint8_t enabled;
  /* BBC slot table is an eight-row display cache, not authoritative storage. */
  char uri[29];
} config_nio_slot_t;

typedef struct {
  uint8_t is_dir;
  char name[CONFIG_NIO_NAME_MAX + 1];
} config_nio_entry_t;

typedef struct {
  uint8_t unused;
} config_nio_prefs_t;

typedef struct {
  uint8_t host_count;
  uint8_t slot_start;
  uint8_t slot_count;
  uint8_t slots_more;
  config_nio_prefs_t prefs;
  uint8_t entry_count;
  uint16_t entry_total;
  uint8_t entries_truncated;
  char browse_path[CONFIG_NIO_PATH_MAX + 1];
  char status[CONFIG_NIO_STATUS_MAX + 1];
} config_nio_state_t;

#define config_nio_set_status(state, msg) do { (void) (state); } while (0)

#ifndef CONFIG_NIO_TABLES_IMPL
int config_nio_bbc_host_get(uint8_t index, char *buf, uint16_t cap);
int config_nio_bbc_host_set(uint8_t index, const char *value);
int config_nio_bbc_host_clear(uint8_t index);
int config_nio_bbc_entry_get(uint8_t index, config_nio_entry_t *entry);
int config_nio_bbc_entry_set(uint8_t index, const config_nio_entry_t *entry);
int config_nio_bbc_slot_get(uint8_t index, config_nio_slot_t *slot);
int config_nio_bbc_slot_set(uint8_t index, const config_nio_slot_t *slot);
int config_nio_bbc_mapping_get(uint8_t unit, config_nio_mapping_t *mapping);
int config_nio_bbc_mapping_set(uint8_t unit, const config_nio_mapping_t *mapping);
int config_nio_bbc_mapping_clear(uint8_t unit);
void config_nio_bbc_invalidate_slot_cache(void);

#define config_nio_host_get(state, index, buf, cap) \
  config_nio_bbc_host_get((index), (buf), (cap))
#define config_nio_host_set(state, index, value) \
  config_nio_bbc_host_set((index), (value))
#define config_nio_host_clear(state, index) \
  config_nio_bbc_host_clear((index))
#define config_nio_entry_get(state, index, entry) \
  config_nio_bbc_entry_get((index), (entry))
#define config_nio_entry_set(state, index, entry) \
  config_nio_bbc_entry_set((index), (entry))
#define config_nio_slot_get(state, index, slot) \
  config_nio_bbc_slot_get((index), (slot))
#define config_nio_slot_set(state, index, slot) \
  config_nio_bbc_slot_set((index), (slot))
#define config_nio_mapping_get(state, unit, mapping) \
  config_nio_bbc_mapping_get((unit), (mapping))
#define config_nio_mapping_set(state, unit, mapping) \
  config_nio_bbc_mapping_set((unit), (mapping))
#define config_nio_mapping_clear(state, unit) \
  config_nio_bbc_mapping_clear((unit))
#endif

#endif
