#include "config_nio.h"
#include "fujinet-nio.h"

#include <string.h>

#define CONFIG_NIO_APPSTORE_BUF_SIZE 64
#define CONFIG_NIO_STORE_BUF_SIZE (CONFIG_NIO_URI_MAX + 1)
#define CONFIG_NIO_APPSTORE_READ_MAX (CONFIG_NIO_APPSTORE_BUF_SIZE - 10)

uint16_t __fastcall__ config_nio_bbc_build_mappings(uint8_t *buf, uint16_t cap);
uint16_t __fastcall__ config_nio_bbc_parse_hosts(config_nio_state_t *state);
void __fastcall__ config_nio_bbc_parse_mappings(uint16_t len);

uint8_t config_nio_store_buf[CONFIG_NIO_STORE_BUF_SIZE];
uint8_t config_nio_appstore_buf[CONFIG_NIO_APPSTORE_BUF_SIZE];
uint16_t config_nio_bbc_parse_len;
uint16_t config_nio_bbc_line_len;
uint8_t config_nio_bbc_parse_finish;
#define store_buf config_nio_store_buf
#define appstore_buf config_nio_appstore_buf
#define line_buf ((char *) store_buf)

static fn_appstore_io_t appstore_io = {
  config_nio_appstore_buf,
  sizeof(config_nio_appstore_buf)
};
static char slot_key_buf[9];

static const char *slot_key(uint8_t index)
{
  uint8_t hundreds = 0;
  uint8_t tens = 0;
  while (index >= 100) { index = (uint8_t) (index - 100); hundreds++; }
  while (index >= 10) { index = (uint8_t) (index - 10); tens++; }
  slot_key_buf[0] = 's'; slot_key_buf[1] = 'l'; slot_key_buf[2] = 'o';
  slot_key_buf[3] = 't'; slot_key_buf[4] = '-';
  slot_key_buf[5] = (char) ('0' + hundreds);
  slot_key_buf[6] = (char) ('0' + tens);
  slot_key_buf[7] = (char) ('0' + index); slot_key_buf[8] = 0;
  return slot_key_buf;
}

int config_nio_read_slot(uint8_t index, config_nio_slot_t *slot)
{
  fn_appstore_read_t rr;
  uint16_t off = 0;
  uint16_t uri_off = 0;
  uint8_t first = 1;
  memset(slot, 0, sizeof(*slot));
  for (;;) {
    uint8_t result = fn_appstore_read(&appstore_io, CONFIG_NIO_NS, slot_key(index),
                                      off, appstore_buf,
                                      CONFIG_NIO_APPSTORE_READ_MAX, &rr);
    uint16_t pos = 0;
    if (result != FN_OK) return 0;
    if (!(rr.flags & FN_APPSTORE_READ_EXISTS)) return 1;
    if (first) {
      if (rr.bytes_read < 2 || appstore_buf[0] != 1) return 0;
      slot->enabled = 1;
      pos = 2; first = 0;
    }
    while (pos < rr.bytes_read) {
      char byte = (char) appstore_buf[pos++];
      if (uri_off + 1 < sizeof(slot->uri)) {
        slot->uri[uri_off++] = byte;
      } else {
        /* This is a display cache: retain the URI tail containing the
         * filename, rather than the host/path prefix. */
        memmove(slot->uri, slot->uri + 1, sizeof(slot->uri) - 2);
        slot->uri[sizeof(slot->uri) - 2] = byte;
      }
    }
    off = (uint16_t) (off + rr.bytes_read);
    if ((rr.flags & FN_APPSTORE_READ_EOF) || rr.bytes_read == 0) break;
  }
  slot->uri[uri_off] = 0;
  return uri_off != 0;
}

int config_nio_write_slot(config_nio_state_t *state, uint8_t index,
                          const char *uri, const char *mode)
{
  fn_appstore_delete_t dr;
  fn_appstore_write_t wr;
  uint16_t uri_len = (uint16_t) strlen(uri);
  uint16_t off = 0;
  uint16_t pos = 0;
  if (!uri_len || uri_len > CONFIG_NIO_URI_MAX) return 0;
  if (fn_appstore_delete(&appstore_io, CONFIG_NIO_NS, slot_key(index), &dr) != FN_OK)
    return 0;
  appstore_buf[0] = 1;
  appstore_buf[1] = (uint8_t) (mode && strcmp(mode, "r") == 0);
  if (fn_appstore_write(&appstore_io, CONFIG_NIO_NS, slot_key(index), 0,
                        appstore_buf, 2, &wr) != FN_OK || wr.bytes_written != 2)
    return 0;
  off = 2;
  while (pos < uri_len) {
    uint16_t chunk = (uint16_t) (uri_len - pos);
    if (chunk > CONFIG_NIO_APPSTORE_READ_MAX) chunk = CONFIG_NIO_APPSTORE_READ_MAX;
    if (fn_appstore_write(&appstore_io, CONFIG_NIO_NS, slot_key(index), off,
                          (const uint8_t *) uri + pos, chunk, &wr) != FN_OK ||
        wr.bytes_written != chunk) return 0;
    off = (uint16_t) (off + chunk); pos = (uint16_t) (pos + chunk);
  }
  return config_nio_refresh_slots(state);
}

int config_nio_delete_slot(config_nio_state_t *state, uint8_t index)
{
  fn_appstore_delete_t dr;
  if (fn_appstore_delete(&appstore_io, CONFIG_NIO_NS, slot_key(index), &dr) != FN_OK)
    return 0;
  return config_nio_refresh_slots(state);
}

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

static void seed_hosts(config_nio_state_t *state)
{
  state->host_count = 3;
  (void) config_nio_host_set(state, 0, "sd0:/");
  (void) config_nio_host_set(state, 1, "fujinet.diller.org");
  (void) config_nio_host_set(state, 2, "fujinet.online");
}

int config_nio_save_hosts(const config_nio_state_t *state)
{
  fn_appstore_delete_t dr;
  uint8_t i;
  uint16_t off;

  off = 0;
  if (fn_appstore_delete(&appstore_io, CONFIG_NIO_NS,
                         CONFIG_NIO_KEY_HOSTS, &dr) != FN_OK)
    return 0;
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
}

int config_nio_save_mappings(const config_nio_state_t *state)
{
  fn_appstore_delete_t dr;
  fn_appstore_write_t wr;
  uint16_t off;
  uint8_t result;

  (void) state;
  if (fn_appstore_delete(&appstore_io, CONFIG_NIO_NS,
                         CONFIG_NIO_KEY_MAPPINGS, &dr) != FN_OK)
    return 0;
  off = config_nio_bbc_build_mappings(store_buf, sizeof(store_buf));
  result = fn_appstore_write(&appstore_io, CONFIG_NIO_NS, CONFIG_NIO_KEY_MAPPINGS,
                             0, store_buf, off, &wr);
  return result == FN_OK && wr.bytes_written == off;
}

int config_nio_save_prefs(const config_nio_state_t *state)
{
  (void) state;
  return 1;
}

int config_nio_load(config_nio_state_t *state)
{
  uint8_t exists;

  if (!state)
    return 0;

  memset(state, 0, sizeof(*state));
  if (!appstore_read_hosts(state, &exists))
    return 0;
  if (state->host_count == 0) {
    seed_hosts(state);
    (void) config_nio_save_hosts(state);
  }

  if (!appstore_read_mappings(state, &exists))
    return 0;

  (void) config_nio_refresh_slots(state);
  config_nio_set_status(state, "Ready");
  return 1;
}
