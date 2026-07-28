#ifndef CONFIG_NIO_H
#define CONFIG_NIO_H

#include "fnctl.h"
#include "fnsvc.h"

#include <stdint.h>

#define CONFIG_NIO_NS "config-nio"
#define CONFIG_NIO_KEY_HOSTS "hosts"
#define CONFIG_NIO_KEY_MAPPINGS "mappings"
#define CONFIG_NIO_KEY_PREFS "prefs"

#define CONFIG_NIO_PREF_DATE_YMD 0
#define CONFIG_NIO_PREF_DATE_YDM 1
#define CONFIG_NIO_PREF_SIZE_FULL 0
#define CONFIG_NIO_PREF_SIZE_COMPACT 1
#define CONFIG_NIO_ENTRY_FLAG_DIR 0x01
#define CONFIG_NIO_ENTRY_FLAG_NAME_TRUNCATED 0x80

#define CONFIG_NIO_COLOR_BODY 0
#define CONFIG_NIO_COLOR_FRAME 1
#define CONFIG_NIO_COLOR_TITLE 2
#define CONFIG_NIO_COLOR_SELECT 3
#define CONFIG_NIO_COLOR_STATUS 4
#define CONFIG_NIO_COLOR_INACTIVE 5
#define CONFIG_NIO_COLOR_INACTIVE_SELECT 6
#define CONFIG_NIO_COLOR_MENUBAR 7
#define CONFIG_NIO_COLOR_MENUHOT 8
#define CONFIG_NIO_COLOR_TITLEBAR 9
#define CONFIG_NIO_COLOR_BUTTON 10
#define CONFIG_NIO_COLOR_BUTTON_SELECT 11
#ifdef CONFIG_NIO_BBC_LITE
#define CONFIG_NIO_COLOR_COUNT 0
#elif defined(__CC65__)
#define CONFIG_NIO_COLOR_COUNT 1
#else
#define CONFIG_NIO_COLOR_COUNT 12
#endif

#ifdef CONFIG_NIO_BBC_LITE
#define CONFIG_NIO_MAX_HOSTS 16
#define CONFIG_NIO_MAX_ENTRIES 12
#define CONFIG_NIO_URI_MAX 128
#define CONFIG_NIO_NAME_MAX 30
#define CONFIG_NIO_TEXT_MAX 768
#define CONFIG_NIO_PATH_MAX 160
#define CONFIG_NIO_STATUS_MAX 0
#elif defined(__CC65__)
#define CONFIG_NIO_MAX_HOSTS 4
#define CONFIG_NIO_MAX_ENTRIES 5
#define CONFIG_NIO_URI_MAX 48
#define CONFIG_NIO_NAME_MAX 31
#define CONFIG_NIO_TEXT_MAX 256
#define CONFIG_NIO_PATH_MAX FNSVC_MAX_PATH
#define CONFIG_NIO_STATUS_MAX 95
#else
#define CONFIG_NIO_MAX_HOSTS 8
#define CONFIG_NIO_MAX_ENTRIES 20
#define CONFIG_NIO_URI_MAX FNSVC_MAX_URI
#define CONFIG_NIO_NAME_MAX 79
#define CONFIG_NIO_TEXT_MAX 1024
#define CONFIG_NIO_PATH_MAX FNSVC_MAX_PATH
#define CONFIG_NIO_STATUS_MAX 95
#endif

typedef struct {
  uint8_t valid;
  uint8_t slot;
  uint8_t readonly;
} config_nio_mapping_t;

typedef struct {
  uint8_t enabled;
  char uri[CONFIG_NIO_URI_MAX + 1];
  char mode[4];
} config_nio_slot_t;

typedef struct {
  uint8_t is_dir;
  char name[CONFIG_NIO_NAME_MAX + 1];
#ifndef CONFIG_NIO_BBC_LITE
  uint32_t size;
  uint32_t mtime;
#endif
} config_nio_entry_t;

typedef struct {
#ifndef CONFIG_NIO_BBC_LITE
  uint8_t date_format;
  uint8_t size_format;
  uint8_t color_fg[CONFIG_NIO_COLOR_COUNT];
  uint8_t color_bg[CONFIG_NIO_COLOR_COUNT];
#else
  uint8_t unused;
#endif
} config_nio_prefs_t;

typedef struct {
  uint8_t host_count;
#ifdef CONFIG_NIO_BBC_LITE
  config_nio_prefs_t prefs;
  uint8_t entry_count;
  uint16_t entry_total;
  uint8_t entries_truncated;
  char browse_path[CONFIG_NIO_PATH_MAX + 1];
  char status[CONFIG_NIO_STATUS_MAX + 1];
#else
  char hosts[CONFIG_NIO_MAX_HOSTS][CONFIG_NIO_URI_MAX + 1];
  config_nio_slot_t slots[FNCTL_MAX_UNITS];
  config_nio_mapping_t mappings[FNCTL_MAX_UNITS];
  config_nio_prefs_t prefs;
  config_nio_entry_t entries[CONFIG_NIO_MAX_ENTRIES];
  uint8_t entry_count;
  uint16_t entry_total;
  uint8_t entries_truncated;
  char browse_path[CONFIG_NIO_PATH_MAX + 1];
  char status[CONFIG_NIO_STATUS_MAX + 1];
#endif
} config_nio_state_t;

int config_nio_load(config_nio_state_t *state);
int config_nio_save_hosts(const config_nio_state_t *state);
int config_nio_save_mappings(const config_nio_state_t *state);
int config_nio_save_prefs(const config_nio_state_t *state);
int config_nio_refresh_slots(config_nio_state_t *state);
#ifdef CONFIG_NIO_BBC_LITE
#define config_nio_set_status(state, msg) do { (void) (state); } while (0)
#else
int config_nio_set_status(config_nio_state_t *state, const char *msg);
#endif
int config_nio_browse(config_nio_state_t *state, uint8_t host);
int config_nio_compose_uri(const char *host, const char *path,
                           const char *leaf, char *out, uint16_t cap);
int config_nio_mount_mappings(config_nio_state_t *state);
void config_nio_run(config_nio_state_t *state);
int config_nio_ui_run(config_nio_state_t *state);
#ifdef CONFIG_NIO_BBC_LITE
int fnsvc_config_nio_list_directory_page(config_nio_state_t *state,
                                         const char *uri,
                                         uint16_t start,
                                         uint8_t max_entries,
                                         uint16_t *next_start,
                                         uint8_t *more);
#endif

void config_nio_ui_clear(void);
void config_nio_ui_header(const char *title, const char *hint);
void config_nio_ui_status(const char *status);
void config_nio_ui_pause(void);
int config_nio_ui_get_key(void);
int config_nio_ui_prompt(const char *label, char *buf, uint16_t cap);
void config_nio_ui_putc(char c);
void config_nio_ui_print(const char *s);
void config_nio_ui_println(const char *s);
void config_nio_ui_print_uint(unsigned value);
void config_nio_ui_print_ulong(unsigned long value);
void config_nio_ui_print_padded(const char *s, uint8_t width);
const char *config_nio_ui_platform_name(void);
uint8_t config_nio_ui_screen_width(void);
uint8_t config_nio_ui_screen_height(void);
void config_nio_ui_drive_label(uint8_t unit, char *buf, uint8_t cap);
int config_nio_ui_show_mappings(config_nio_state_t *state);

#if defined(CONFIG_NIO_BBC_LITE) && !defined(CONFIG_NIO_TABLES_IMPL)
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
#else
int config_nio_host_get(const config_nio_state_t *state, uint8_t index,
                        char *buf, uint16_t cap);
int config_nio_host_set(config_nio_state_t *state, uint8_t index,
                        const char *value);
int config_nio_host_clear(config_nio_state_t *state, uint8_t index);
int config_nio_entry_get(const config_nio_state_t *state, uint8_t index,
                         config_nio_entry_t *entry);
int config_nio_entry_set(config_nio_state_t *state, uint8_t index,
                         const config_nio_entry_t *entry);
int config_nio_slot_get(const config_nio_state_t *state, uint8_t index,
                        config_nio_slot_t *slot);
int config_nio_slot_set(config_nio_state_t *state, uint8_t index,
                        const config_nio_slot_t *slot);
int config_nio_mapping_get(const config_nio_state_t *state, uint8_t unit,
                           config_nio_mapping_t *mapping);
int config_nio_mapping_set(config_nio_state_t *state, uint8_t unit,
                           const config_nio_mapping_t *mapping);
int config_nio_mapping_clear(config_nio_state_t *state, uint8_t unit);
#endif

#endif
