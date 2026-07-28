#include "config_nio.h"
#include "fujinet-nio.h"

#include <stdlib.h>
#include <string.h>

#ifdef CONFIG_NIO_BBC_LITE
#define CONFIG_NIO_APPSTORE_BUF_SIZE 64
#define CONFIG_NIO_STORE_BUF_SIZE (CONFIG_NIO_URI_MAX + 1)
uint16_t __fastcall__ config_nio_bbc_build_mappings(uint8_t *buf, uint16_t cap);
uint16_t __fastcall__ config_nio_bbc_parse_hosts(config_nio_state_t *state);
void __fastcall__ config_nio_bbc_parse_mappings(uint16_t len);
uint16_t config_nio_bbc_parse_len;
uint16_t config_nio_bbc_line_len;
uint8_t config_nio_bbc_parse_finish;
#elif defined(__CC65__)
#define CONFIG_NIO_APPSTORE_BUF_SIZE 512
#define CONFIG_NIO_STORE_BUF_SIZE (CONFIG_NIO_TEXT_MAX + 1)
#else
#define CONFIG_NIO_APPSTORE_BUF_SIZE 1024
#define CONFIG_NIO_STORE_BUF_SIZE (CONFIG_NIO_TEXT_MAX + 1)
#endif

#ifdef CONFIG_NIO_BBC_LITE
uint8_t config_nio_store_buf[CONFIG_NIO_STORE_BUF_SIZE];
uint8_t config_nio_appstore_buf[CONFIG_NIO_APPSTORE_BUF_SIZE];
#define store_buf config_nio_store_buf
#define appstore_buf config_nio_appstore_buf
#else
static uint8_t store_buf[CONFIG_NIO_STORE_BUF_SIZE];
static uint8_t appstore_buf[CONFIG_NIO_APPSTORE_BUF_SIZE];
#endif
static fn_appstore_io_t appstore_io = { appstore_buf, sizeof(appstore_buf) };
#ifdef CONFIG_NIO_BBC_LITE
#define line_buf ((char *) store_buf)
#else
static char line_buf[CONFIG_NIO_URI_MAX + 1];
static char host_tmp[CONFIG_NIO_URI_MAX + 1];
#endif

#define CONFIG_NIO_APPSTORE_READ_MAX (CONFIG_NIO_APPSTORE_BUF_SIZE - 10)

#ifndef CONFIG_NIO_BBC_LITE
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
#endif

#ifndef CONFIG_NIO_BBC_LITE
static int appstore_read_text(const char *key, char *buf, uint16_t cap,
                              uint8_t *exists)
{
  fn_appstore_read_t rr;
  uint16_t max_read;
  uint8_t result;
  uint16_t n;

  if (cap == 0)
    return 0;

  buf[0] = 0;
  if (exists)
    *exists = 0;

  max_read = (uint16_t) (cap - 1);
  if (max_read > CONFIG_NIO_APPSTORE_READ_MAX)
    max_read = CONFIG_NIO_APPSTORE_READ_MAX;

  result = fn_appstore_read(&appstore_io, CONFIG_NIO_NS, key, 0, appstore_buf,
                            max_read, &rr);
  if (result != FN_OK)
    return 0;
  if ((rr.flags & FN_APPSTORE_READ_EXISTS) == 0)
    return 1;

  n = rr.bytes_read;
  if (n >= cap)
    n = (uint16_t) (cap - 1);
  memcpy(buf, appstore_buf, n);
  buf[n] = 0;
  if (exists)
    *exists = 1;
  return 1;
}
#endif

#ifndef CONFIG_NIO_BBC_LITE
static int appstore_write_text(const char *key, const char *buf)
{
  fn_appstore_write_t wr;
  uint16_t len;
  uint8_t result;

  len = (uint16_t) strlen(buf);
  result = fn_appstore_write(&appstore_io, CONFIG_NIO_NS, key, 0, (const uint8_t *) buf,
                             len, &wr);
  return result == FN_OK && wr.bytes_written == len;
}
#endif

#ifdef CONFIG_NIO_BBC_LITE
static int appstore_write_chunk(const char *key, uint16_t *off,
                                const char *buf, uint16_t len)
{
  fn_appstore_write_t wr;
  uint8_t result;

  result = fn_appstore_write(&appstore_io, CONFIG_NIO_NS, key, *off,
                             (const uint8_t *) buf, len, &wr);
  if (result != FN_OK || wr.bytes_written != len)
    return 0;
  *off = (uint16_t) (*off + len);
  return 1;
}

static int appstore_write_chunks(const char *key, uint16_t *off,
                                 const char *buf, uint16_t len)
{
  uint16_t pos;
  uint16_t chunk;
  uint16_t max_chunk;

  max_chunk = CONFIG_NIO_APPSTORE_BUF_SIZE - 26;
  pos = 0;
  while (pos < len) {
    chunk = (uint16_t) (len - pos);
    if (chunk > max_chunk)
      chunk = max_chunk;
    if (!appstore_write_chunk(key, off, &buf[pos], chunk))
      return 0;
    pos = (uint16_t) (pos + chunk);
  }
  return 1;
}

static int appstore_read_hosts(config_nio_state_t *state, uint8_t *exists)
{
  fn_appstore_read_t rr;
  uint16_t off;
  uint8_t result;

  state->host_count = 0;
  config_nio_bbc_line_len = 0;
  off = 0;
  if (exists)
    *exists = 0;

  for (;;) {
    result = fn_appstore_read(&appstore_io, CONFIG_NIO_NS, CONFIG_NIO_KEY_HOSTS,
                              off, appstore_buf, CONFIG_NIO_APPSTORE_READ_MAX,
                              &rr);
    if (result != FN_OK)
      return 0;
    if ((rr.flags & FN_APPSTORE_READ_EXISTS) == 0)
      return 1;
    if (exists)
      *exists = 1;
    config_nio_bbc_parse_len = rr.bytes_read;
    config_nio_bbc_parse_finish = 0;
    config_nio_bbc_line_len = config_nio_bbc_parse_hosts(state);
    off = (uint16_t) (off + rr.bytes_read);
    if ((rr.flags & FN_APPSTORE_READ_EOF) || rr.bytes_read == 0) {
      config_nio_bbc_parse_len = 0;
      config_nio_bbc_parse_finish = 1;
      config_nio_bbc_line_len = config_nio_bbc_parse_hosts(state);
      return 1;
    }
  }
}
#endif

#ifndef CONFIG_NIO_BBC_LITE
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
#endif

static void seed_hosts(config_nio_state_t *state)
{
  state->host_count = 3;
  (void) config_nio_host_set(state, 0, "sd0:/");
  (void) config_nio_host_set(state, 1, "fujinet.diller.org");
  (void) config_nio_host_set(state, 2, "fujinet.online");
}

static void seed_prefs(config_nio_state_t *state)
{
#ifndef CONFIG_NIO_BBC_LITE
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
#else
  (void) state;
#endif
}

#ifndef CONFIG_NIO_BBC_LITE
static void parse_hosts(config_nio_state_t *state, const char *text)
{
  const char *p;

  state->host_count = 0;
  p = text;
  while (next_line(&p, line_buf, sizeof(line_buf)) &&
         state->host_count < CONFIG_NIO_MAX_HOSTS) {
    if (!line_buf[0])
      continue;
#ifndef CONFIG_NIO_BBC_LITE
    strncpy(host_tmp, line_buf, CONFIG_NIO_URI_MAX);
    host_tmp[CONFIG_NIO_URI_MAX] = 0;
    (void) config_nio_host_set(state, state->host_count, host_tmp);
#else
    (void) config_nio_host_set(state, state->host_count, line_buf);
#endif
    state->host_count++;
  }
}
#endif

#ifdef CONFIG_NIO_BBC_LITE
static int appstore_read_mappings(config_nio_state_t *state, uint8_t *exists)
{
  fn_appstore_read_t rr;
  uint8_t result;

  (void) state;

  if (exists)
    *exists = 0;
  result = fn_appstore_read(&appstore_io, CONFIG_NIO_NS, CONFIG_NIO_KEY_MAPPINGS,
                            0, appstore_buf, CONFIG_NIO_APPSTORE_READ_MAX,
                            &rr);
  if (result != FN_OK)
    return 0;
  if ((rr.flags & FN_APPSTORE_READ_EXISTS) == 0)
    return 1;
  if (exists)
    *exists = 1;

  config_nio_bbc_parse_mappings(rr.bytes_read);
  return 1;
}
#else
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
    int slot;

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
    slot = atoi(b);
    if (unit < 0 || unit >= FNCTL_MAX_UNITS || slot < 0 || slot >= FNCTL_MAX_UNITS)
      continue;

    {
      config_nio_mapping_t mapping;

      mapping.valid = 1;
      mapping.slot = (uint8_t) slot;
      mapping.readonly =
        (uint8_t) (strcmp(c, "ro") == 0 || strcmp(c, "RO") == 0);
      (void) config_nio_mapping_set(state, (uint8_t) unit, &mapping);
    }
  }
}
#endif

#ifndef CONFIG_NIO_BBC_LITE
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
#endif

int config_nio_save_hosts(const config_nio_state_t *state)
{
  uint8_t i;
  uint16_t off;

#ifdef CONFIG_NIO_BBC_LITE
  off = 0;
  for (i = 0; i < state->host_count; i++) {
    uint16_t len;

    if (!config_nio_host_get(state, i, line_buf, CONFIG_NIO_STORE_BUF_SIZE))
      continue;
    len = (uint16_t) strlen(line_buf);
    if (len >= sizeof(store_buf))
      return 0;
    line_buf[len++] = '\n';
    if (!appstore_write_chunks(CONFIG_NIO_KEY_HOSTS, &off, line_buf, len))
      return 0;
  }
  return 1;
#else
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
#endif
}

int config_nio_save_mappings(const config_nio_state_t *state)
{
  uint8_t unit;
  uint16_t off;

#ifdef CONFIG_NIO_BBC_LITE
  fn_appstore_write_t wr;
  uint8_t result;

  (void) state;
  (void) unit;
  off = config_nio_bbc_build_mappings(store_buf, sizeof(store_buf));
  result = fn_appstore_write(&appstore_io, CONFIG_NIO_NS, CONFIG_NIO_KEY_MAPPINGS,
                             0, store_buf, off, &wr);
  return result == FN_OK && wr.bytes_written == off;
#else
  off = 0;
  store_buf[0] = 0;
  for (unit = 0; unit < FNCTL_MAX_UNITS; unit++) {
    config_nio_mapping_t mapping;

    if (!config_nio_mapping_get(state, unit, &mapping) || !mapping.valid)
      continue;
    if ((uint16_t) (off + 8) >= sizeof(store_buf))
      return 0;
    append_digit((char *) store_buf, &off, unit);
    store_buf[off++] = '\t';
    append_digit((char *) store_buf, &off, mapping.slot);
    store_buf[off++] = '\t';
    store_buf[off++] = mapping.readonly ? 'r' : 'r';
    store_buf[off++] = mapping.readonly ? 'o' : 'w';
    store_buf[off++] = '\n';
    store_buf[off] = 0;
  }
  return appstore_write_text(CONFIG_NIO_KEY_MAPPINGS, (const char *) store_buf);
#endif
}

int config_nio_save_prefs(const config_nio_state_t *state)
{
#ifndef CONFIG_NIO_BBC_LITE
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
#else
  (void) state;
  return 1;
#endif
}

int config_nio_load(config_nio_state_t *state)
{
  uint8_t exists;

  if (!state)
    return 0;

  memset(state, 0, sizeof(*state));
  seed_prefs(state);
#ifdef CONFIG_NIO_BBC_LITE
  if (!appstore_read_hosts(state, &exists))
    return 0;
#else
  if (!appstore_read_text(CONFIG_NIO_KEY_HOSTS, (char *) store_buf,
                          sizeof(store_buf), &exists))
    return 0;
  if (exists)
    parse_hosts(state, (const char *) store_buf);
#endif
  if (state->host_count == 0) {
    seed_hosts(state);
    (void) config_nio_save_hosts(state);
  }

#ifdef CONFIG_NIO_BBC_LITE
  if (!appstore_read_mappings(state, &exists))
    return 0;
#else
  if (!appstore_read_text(CONFIG_NIO_KEY_MAPPINGS, (char *) store_buf,
                          sizeof(store_buf), &exists))
    return 0;
  if (exists)
    parse_mappings(state, (const char *) store_buf);
#endif

#ifndef CONFIG_NIO_BBC_LITE
  if (!appstore_read_text(CONFIG_NIO_KEY_PREFS, (char *) store_buf,
                          sizeof(store_buf), &exists))
    return 0;
  if (exists)
    parse_prefs(state, (const char *) store_buf);
#endif

  (void) config_nio_refresh_slots(state);
  config_nio_set_status(state, "Ready");
  return 1;
}
