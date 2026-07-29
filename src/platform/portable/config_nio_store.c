#include "config_nio.h"
#include "fujinet-nio.h"

#include <stdlib.h>
#include <string.h>

#if defined(__CC65__)
#define CONFIG_NIO_APPSTORE_BUF_SIZE 512
#define CONFIG_NIO_SLOT_STORE_SIZE 2048
#else
#define CONFIG_NIO_APPSTORE_BUF_SIZE 1024
#define CONFIG_NIO_SLOT_STORE_SIZE 16384
#endif

#define CONFIG_NIO_STORE_BUF_SIZE (CONFIG_NIO_TEXT_MAX + 1)
#define CONFIG_NIO_APPSTORE_READ_MAX (CONFIG_NIO_APPSTORE_BUF_SIZE - 10)

static uint8_t store_buf[CONFIG_NIO_STORE_BUF_SIZE];
static uint8_t slot_store_buf[CONFIG_NIO_SLOT_STORE_SIZE];
static uint8_t appstore_buf[CONFIG_NIO_APPSTORE_BUF_SIZE];
static fn_appstore_io_t appstore_io = { appstore_buf, sizeof(appstore_buf) };
static char line_buf[CONFIG_NIO_URI_MAX + 10];
static char host_tmp[CONFIG_NIO_URI_MAX + 1];

static void append_digit(char *buf, uint16_t *off, uint8_t value)
{
  buf[*off] = (char) ('0' + value);
  *off = (uint16_t) (*off + 1);
  buf[*off] = 0;
}

static void append_uint(char *buf, uint16_t *off, uint8_t value)
{
  if (value >= 10)
    append_digit(buf, off, (uint8_t) (value / 10));
  append_digit(buf, off, (uint8_t) (value % 10));
}

static void append_text(char *buf, uint16_t *off, const char *text)
{
  while (text && *text) {
    buf[*off] = *text++;
    *off = (uint16_t) (*off + 1);
  }
  buf[*off] = 0;
}

static int appstore_read_text(const char *key, char *buf, uint16_t cap,
                              uint8_t *exists)
{
  fn_appstore_read_t rr;
  uint16_t max_read;
  uint8_t result;
  uint16_t total;

  if (cap == 0)
    return 0;

  buf[0] = 0;
  if (exists)
    *exists = 0;

  max_read = (uint16_t) (cap - 1);
  if (max_read > CONFIG_NIO_APPSTORE_READ_MAX)
    max_read = CONFIG_NIO_APPSTORE_READ_MAX;

  total = 0;
  do {
    uint16_t want;
    want = (uint16_t) (cap - 1 - total);
    if (want > max_read)
      want = max_read;
    if (want == 0)
      return 0;
    result = fn_appstore_read(&appstore_io, CONFIG_NIO_NS, key, total,
                              appstore_buf, want, &rr);
    if (result != FN_OK)
      return 0;
    if ((rr.flags & FN_APPSTORE_READ_EXISTS) == 0)
      return 1;
    if (exists)
      *exists = 1;
    memcpy(buf + total, appstore_buf, rr.bytes_read);
    total = (uint16_t) (total + rr.bytes_read);
    buf[total] = 0;
  } while ((rr.flags & FN_APPSTORE_READ_EOF) == 0 && rr.bytes_read != 0);
  return 1;
}

static int appstore_write_text(const char *key, const char *buf)
{
  fn_appstore_write_t wr;
  uint16_t len;
  uint16_t off;

  len = (uint16_t) strlen(buf);
  off = 0;
  if (len == 0) {
    return fn_appstore_write(&appstore_io, CONFIG_NIO_NS, key, 0,
                             (const uint8_t *) "", 0, &wr) == FN_OK;
  }
  while (off < len) {
    uint16_t chunk;
    chunk = (uint16_t) (len - off);
    if (chunk > CONFIG_NIO_APPSTORE_READ_MAX)
      chunk = CONFIG_NIO_APPSTORE_READ_MAX;
    if (fn_appstore_write(&appstore_io, CONFIG_NIO_NS, key, off,
                          (const uint8_t *) buf + off, chunk, &wr) != FN_OK ||
        wr.bytes_written != chunk)
      return 0;
    off = (uint16_t) (off + chunk);
  }
  return 1;
}

static void trim_line(char *s)
{
  char *p;

  p = strchr(s, '\n');
  if (p)
    *p = 0;
  p = strchr(s, '\r');
  if (p)
    *p = 0;
}

static int next_line(const char **src, char *out, uint16_t cap)
{
  const char *p;
  uint16_t len;

  if (!src || !*src || !**src || cap == 0)
    return 0;

  p = *src;
  len = 0;
  while (p[len] && p[len] != '\n' && p[len] != '\r' && len < (uint16_t) (cap - 1)) {
    out[len] = p[len];
    len++;
  }
  out[len] = 0;

  while (p[len] && p[len] != '\n' && p[len] != '\r')
    len++;
  while (p[len] == '\n' || p[len] == '\r')
    len++;
  *src = &p[len];
  trim_line(out);
  return 1;
}

static void seed_hosts(config_nio_state_t *state)
{
  state->host_count = 3;
  (void) config_nio_host_set(state, 0, "sd0:/");
  (void) config_nio_host_set(state, 1, "fujinet.diller.org");
  (void) config_nio_host_set(state, 2, "fujinet.online");
}

static void seed_prefs(config_nio_state_t *state)
{
  config_nio_prefs_t *prefs;

  prefs = &state->prefs;
  prefs->date_format = CONFIG_NIO_PREF_DATE_YMD;
  prefs->size_format = CONFIG_NIO_PREF_SIZE_FULL;

#if !defined(__CC65__)
  prefs->color_fg[CONFIG_NIO_COLOR_BODY] = 7;
  prefs->color_bg[CONFIG_NIO_COLOR_BODY] = 1;
  prefs->color_fg[CONFIG_NIO_COLOR_FRAME] = 3;
  prefs->color_bg[CONFIG_NIO_COLOR_FRAME] = 1;
  prefs->color_fg[CONFIG_NIO_COLOR_TITLE] = 6;
  prefs->color_bg[CONFIG_NIO_COLOR_TITLE] = 1;
  prefs->color_fg[CONFIG_NIO_COLOR_SELECT] = 0;
  prefs->color_bg[CONFIG_NIO_COLOR_SELECT] = 3;
  prefs->color_fg[CONFIG_NIO_COLOR_STATUS] = 0;
  prefs->color_bg[CONFIG_NIO_COLOR_STATUS] = 3;
  prefs->color_fg[CONFIG_NIO_COLOR_INACTIVE] = 7;
  prefs->color_bg[CONFIG_NIO_COLOR_INACTIVE] = 1;
  prefs->color_fg[CONFIG_NIO_COLOR_INACTIVE_SELECT] = 7;
  prefs->color_bg[CONFIG_NIO_COLOR_INACTIVE_SELECT] = 5;
  prefs->color_fg[CONFIG_NIO_COLOR_MENUBAR] = 0;
  prefs->color_bg[CONFIG_NIO_COLOR_MENUBAR] = 7;
  prefs->color_fg[CONFIG_NIO_COLOR_MENUHOT] = 4;
  prefs->color_bg[CONFIG_NIO_COLOR_MENUHOT] = 7;
  prefs->color_fg[CONFIG_NIO_COLOR_TITLEBAR] = 0;
  prefs->color_bg[CONFIG_NIO_COLOR_TITLEBAR] = 3;
  prefs->color_fg[CONFIG_NIO_COLOR_BUTTON] = 0;
  prefs->color_bg[CONFIG_NIO_COLOR_BUTTON] = 7;
  prefs->color_fg[CONFIG_NIO_COLOR_BUTTON_SELECT] = 7;
  prefs->color_bg[CONFIG_NIO_COLOR_BUTTON_SELECT] = 1;
#else
  prefs->color_fg[0] = 7;
  prefs->color_bg[0] = 1;
#endif
}

static void parse_hosts(config_nio_state_t *state, const char *text)
{
  const char *p;

  state->host_count = 0;
  p = text;
  while (next_line(&p, line_buf, sizeof(line_buf)) &&
         state->host_count < CONFIG_NIO_MAX_HOSTS) {
    if (!line_buf[0])
      continue;
    strncpy(host_tmp, line_buf, CONFIG_NIO_URI_MAX);
    host_tmp[CONFIG_NIO_URI_MAX] = 0;
    (void) config_nio_host_set(state, state->host_count, host_tmp);
    state->host_count++;
  }
}

static void parse_mappings(config_nio_state_t *state, const char *text)
{
  const char *p;
  uint8_t i;

  for (i = 0; i < FNCTL_MAX_UNITS; i++)
    (void) config_nio_mapping_clear(state, i);
  p = text;
  while (next_line(&p, line_buf, sizeof(line_buf))) {
    char *a;
    char *b;
    char *c;
    int unit;

    a = line_buf;
    b = strchr(a, '\t');
    if (!b)
      continue;
    *b++ = 0;
    c = strchr(b, '\t');
    if (!c)
      continue;
    *c++ = 0;

    unit = atoi(a);
    if (unit < 0 || unit >= FNCTL_MAX_UNITS || !b[0])
      continue;

    {
      config_nio_mapping_t mapping;

      memset(&mapping, 0, sizeof(mapping));
      mapping.valid = 1;
      strncpy(mapping.uri, b, CONFIG_NIO_URI_MAX);
      mapping.uri[CONFIG_NIO_URI_MAX] = 0;
      mapping.readonly =
        (uint8_t) (strcmp(c, "ro") == 0 || strcmp(c, "RO") == 0);
      (void) config_nio_mapping_set(state, (uint8_t) unit, &mapping);
    }
  }
}

static void parse_prefs(config_nio_state_t *state, const char *text)
{
  const char *p;

  p = text;
  while (next_line(&p, line_buf, sizeof(line_buf))) {
    char *a;
    char *b;
    int index;
    int fg;
    int bg;

    if (strncmp(line_buf, "date=", 5) == 0) {
      if (strcmp(line_buf + 5, "ydm") == 0)
        state->prefs.date_format = CONFIG_NIO_PREF_DATE_YDM;
      else
        state->prefs.date_format = CONFIG_NIO_PREF_DATE_YMD;
      continue;
    }
    if (strncmp(line_buf, "size=", 5) == 0) {
      if (strcmp(line_buf + 5, "compact") == 0)
        state->prefs.size_format = CONFIG_NIO_PREF_SIZE_COMPACT;
      else
        state->prefs.size_format = CONFIG_NIO_PREF_SIZE_FULL;
      continue;
    }
    if (strncmp(line_buf, "color", 5) != 0)
      continue;
    a = strchr(line_buf, '=');
    if (!a)
      continue;
    *a++ = 0;
    b = strchr(a, ',');
    if (!b)
      continue;
    *b++ = 0;
    index = atoi(line_buf + 5);
    fg = atoi(a);
    bg = atoi(b);
    if (index < 0 || index >= CONFIG_NIO_COLOR_COUNT ||
        fg < 0 || fg > 7 || bg < 0 || bg > 7)
      continue;
    state->prefs.color_fg[index] = (uint8_t) fg;
    state->prefs.color_bg[index] = (uint8_t) bg;
  }
}

int config_nio_save_hosts(const config_nio_state_t *state)
{
  uint8_t i;
  uint16_t off;

  off = 0;
  store_buf[0] = 0;
  for (i = 0; i < state->host_count; i++) {
    uint16_t len;
    char host[CONFIG_NIO_URI_MAX + 1];

    if (!config_nio_host_get(state, i, host, sizeof(host)))
      continue;
    len = (uint16_t) strlen(host);
    if ((uint16_t) (off + len + 1) >= sizeof(store_buf))
      return 0;
    memcpy(&store_buf[off], host, len);
    off = (uint16_t) (off + len);
    store_buf[off++] = '\n';
    store_buf[off] = 0;
  }
  return appstore_write_text(CONFIG_NIO_KEY_HOSTS, (const char *) store_buf);
}

int config_nio_save_mappings(const config_nio_state_t *state)
{
  uint8_t unit;
  uint16_t off;

  off = 0;
  store_buf[0] = 0;
  for (unit = 0; unit < FNCTL_MAX_UNITS; unit++) {
    config_nio_mapping_t mapping;

    if (!config_nio_mapping_get(state, unit, &mapping) || !mapping.valid)
      continue;
    if ((uint16_t) (off + strlen(mapping.uri) + 8) >= sizeof(store_buf))
      return 0;
    append_digit((char *) store_buf, &off, unit);
    store_buf[off++] = '\t';
    append_text((char *) store_buf, &off, mapping.uri);
    store_buf[off++] = '\t';
    store_buf[off++] = mapping.readonly ? 'r' : 'r';
    store_buf[off++] = mapping.readonly ? 'o' : 'w';
    store_buf[off++] = '\n';
    store_buf[off] = 0;
  }
  return appstore_write_text(CONFIG_NIO_KEY_MAPPINGS, (const char *) store_buf);
}

static int load_slots_text(uint8_t *exists)
{
  return appstore_read_text(CONFIG_NIO_KEY_SLOTS, (char *) slot_store_buf,
                            sizeof(slot_store_buf), exists);
}

static int slot_line(const char *uri, const char *mode, char *out, uint16_t cap)
{
  uint16_t mode_len;
  uint16_t uri_len;
  if (!uri || !uri[0] || strchr(uri, '\t') || strchr(uri, '\n') || strchr(uri, '\r'))
    return 0;
  if (!mode || !mode[0])
    mode = "rw";
  mode_len = (uint16_t) strlen(mode);
  uri_len = (uint16_t) strlen(uri);
  if ((uint16_t) (mode_len + uri_len + 3) > cap)
    return 0;
  memcpy(out, mode, mode_len);
  out[mode_len] = '\t';
  memcpy(out + mode_len + 1, uri, uri_len);
  out[mode_len + 1 + uri_len] = '\n';
  out[mode_len + 2 + uri_len] = 0;
  return 1;
}

static int find_slot_line(char *text, uint16_t index, char **start, char **end)
{
  uint16_t current;
  char *p;
  current = 0;
  p = text;
  while (*p) {
    char *line_end;
    line_end = strchr(p, '\n');
    if (!line_end)
      line_end = p + strlen(p);
    else
      line_end++;
    if (current == index) {
      *start = p;
      *end = line_end;
      return 1;
    }
    current++;
    p = line_end;
  }
  return 0;
}

static int replace_slot_line(uint16_t index, const char *replacement)
{
  uint8_t exists;
  char *start;
  char *end;
  uint16_t total;
  uint16_t old_len;
  uint16_t new_len;
  if (!load_slots_text(&exists))
    return 0;
  if (!find_slot_line((char *) slot_store_buf, index, &start, &end))
    return 0;
  total = (uint16_t) strlen((char *) slot_store_buf);
  old_len = (uint16_t) (end - start);
  new_len = (uint16_t) strlen(replacement);
  if ((uint32_t) total - old_len + new_len >= sizeof(slot_store_buf))
    return 0;
  memmove(start + new_len, end, (size_t) (total - (end - (char *) slot_store_buf) + 1));
  if (new_len)
    memcpy(start, replacement, new_len);
  return appstore_write_text(CONFIG_NIO_KEY_SLOTS, (const char *) slot_store_buf);
}

int config_nio_refresh_slots(config_nio_state_t *state)
{
  uint8_t exists;
  const char *p;
  uint16_t index;
  uint8_t visible;
  uint8_t i;
  if (!state || !load_slots_text(&exists))
    return 0;
  for (i = 0; i < FNCTL_MAX_UNITS; i++)
    memset(&state->slots[i], 0, sizeof(state->slots[i]));
  p = (const char *) slot_store_buf;
  index = 0;
  visible = 0;
  while (*p) {
    const char *end;
    const char *tab;
    uint16_t len;
    end = strchr(p, '\n');
    if (!end)
      end = p + strlen(p);
    len = (uint16_t) (end - p);
    if (index >= state->slot_start && visible < FNCTL_MAX_UNITS) {
      config_nio_slot_t *slot;
      uint16_t mode_len;
      uint16_t uri_len;
      slot = &state->slots[visible++];
      tab = (const char *) memchr(p, '\t', len);
      if (tab) {
        mode_len = (uint16_t) (tab - p);
        if (mode_len > 3) mode_len = 3;
        memcpy(slot->mode, p, mode_len);
        slot->mode[mode_len] = 0;
        uri_len = (uint16_t) (len - (tab + 1 - p));
        if (uri_len > CONFIG_NIO_URI_MAX) uri_len = CONFIG_NIO_URI_MAX;
        memcpy(slot->uri, tab + 1, uri_len);
        slot->uri[uri_len] = 0;
        slot->enabled = slot->uri[0] != 0;
      }
    }
    index++;
    p = *end ? end + 1 : end;
  }
  if (state->slot_start >= index && index) {
    state->slot_start = (uint16_t) (((index - 1) / FNCTL_MAX_UNITS) * FNCTL_MAX_UNITS);
    return config_nio_refresh_slots(state);
  }
  state->slot_count = visible;
  state->slots_more = index > (uint16_t) (state->slot_start + visible);
  return 1;
}

int config_nio_add_slot(config_nio_state_t *state, const char *uri, const char *mode)
{
  uint8_t exists;
  uint16_t total;
  if (!state || !slot_line(uri, mode, line_buf, sizeof(line_buf)) ||
      !load_slots_text(&exists))
    return 0;
  total = (uint16_t) strlen((char *) slot_store_buf);
  if ((uint32_t) total + strlen(line_buf) >= sizeof(slot_store_buf))
    return 0;
  strcpy((char *) slot_store_buf + total, line_buf);
  if (!appstore_write_text(CONFIG_NIO_KEY_SLOTS, (const char *) slot_store_buf))
    return 0;
  return config_nio_refresh_slots(state);
}

int config_nio_update_slot(config_nio_state_t *state, uint8_t visible_index,
                           const char *uri, const char *mode)
{
  if (!state || visible_index >= state->slot_count ||
      !slot_line(uri, mode, line_buf, sizeof(line_buf)))
    return 0;
  if (!replace_slot_line((uint16_t) (state->slot_start + visible_index), line_buf))
    return 0;
  return config_nio_refresh_slots(state);
}

int config_nio_delete_slot(config_nio_state_t *state, uint8_t visible_index)
{
  if (!state || visible_index >= state->slot_count)
    return 0;
  if (!replace_slot_line((uint16_t) (state->slot_start + visible_index), ""))
    return 0;
  return config_nio_refresh_slots(state);
}

int config_nio_save_prefs(const config_nio_state_t *state)
{
  uint8_t i;
  uint16_t off;
  const char *date_value;
  const char *size_value;

  off = 0;
  store_buf[0] = 0;
  date_value = state->prefs.date_format == CONFIG_NIO_PREF_DATE_YDM ? "ydm" : "ymd";
  size_value = state->prefs.size_format == CONFIG_NIO_PREF_SIZE_COMPACT ? "compact" : "full";
  append_text((char *) store_buf, &off, "date=");
  append_text((char *) store_buf, &off, date_value);
  append_text((char *) store_buf, &off, "\nsize=");
  append_text((char *) store_buf, &off, size_value);
  append_text((char *) store_buf, &off, "\n");
  for (i = 0; i < CONFIG_NIO_COLOR_COUNT; i++) {
    if ((uint16_t) (off + 16) >= sizeof(store_buf))
      return 0;
    append_text((char *) store_buf, &off, "color");
    append_uint((char *) store_buf, &off, i);
    store_buf[off++] = '=';
    store_buf[off] = 0;
    append_uint((char *) store_buf, &off, state->prefs.color_fg[i]);
    store_buf[off++] = ',';
    store_buf[off] = 0;
    append_uint((char *) store_buf, &off, state->prefs.color_bg[i]);
    store_buf[off++] = '\n';
    store_buf[off] = 0;
  }
  return appstore_write_text(CONFIG_NIO_KEY_PREFS, (const char *) store_buf);
}

int config_nio_load(config_nio_state_t *state)
{
  uint8_t exists;

  if (!state)
    return 0;

  memset(state, 0, sizeof(*state));
  seed_prefs(state);
  if (!appstore_read_text(CONFIG_NIO_KEY_HOSTS, (char *) store_buf,
                          sizeof(store_buf), &exists))
    return 0;
  if (exists)
    parse_hosts(state, (const char *) store_buf);
  if (state->host_count == 0) {
    seed_hosts(state);
    (void) config_nio_save_hosts(state);
  }

  if (!appstore_read_text(CONFIG_NIO_KEY_MAPPINGS, (char *) store_buf,
                          sizeof(store_buf), &exists))
    return 0;
  if (exists)
    parse_mappings(state, (const char *) store_buf);

  if (!appstore_read_text(CONFIG_NIO_KEY_PREFS, (char *) store_buf,
                          sizeof(store_buf), &exists))
    return 0;
  if (exists)
    parse_prefs(state, (const char *) store_buf);

  (void) config_nio_refresh_slots(state);
  config_nio_set_status(state, "Ready");
  return 1;
}
