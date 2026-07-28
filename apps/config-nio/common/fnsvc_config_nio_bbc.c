#include "config_nio.h"
#include "fnsvc.h"

#include "fn_bbc_internal.h"
#include "fujinet-nio.h"

#include <stddef.h>
#include <string.h>

enum {
  NIO_DEVICEID_FUJI = 0x70,
  NIO_DEVICEID_DISK = 0xFC,
  NIO_DEVICEID_FILE = 0xFE
};

enum {
  NIO_FUJI_GET_MOUNT = 0xFB,
  NIO_FUJI_SET_MOUNT = 0xFC
};

enum {
  NIO_DISK_VERSION = 1,
  NIO_DISK_MOUNT = 0x01
};

enum {
  NIO_FILE_VERSION = 1,
  NIO_FILE_LIST_DIRECTORY = 0x02
};

enum {
  NIO_FILE_LIST_FLAG_COMPACT = 0x01,
  NIO_FILE_LIST_FLAG_SORT_BY_NAME = 0x02,
  NIO_FILE_LIST_RESP_MORE = 0x01,
  NIO_FILE_LIST_ENTRY_TRUNCATED = 0x80
};

#ifndef FNSVC_LIST_MAX_PAYLOAD
#define FNSVC_LIST_MAX_PAYLOAD 120
#endif

#define BBC_REQ_BUF_SIZE 170
#define BBC_RESP_BUF_SIZE (FNSVC_LIST_MAX_PAYLOAD + 10)
#define BBC_LIST_REQUEST_OVERHEAD 7
#define BBC_SET_MOUNT_REQUEST_OVERHEAD 4
#define BBC_LIST_NAME_MAX CONFIG_NIO_NAME_MAX

uint8_t fnsvc_bbc_req_buf[BBC_REQ_BUF_SIZE];
uint8_t fnsvc_bbc_resp_buf[BBC_RESP_BUF_SIZE];
uint8_t fnsvc_bbc_last_error;
uint8_t fnsvc_bbc_last_status;
uint8_t fnsvc_bbc_last_raw_error;
uint16_t fnsvc_bbc_last_response_len;
#ifndef CONFIG_NIO_BBC_LITE
static config_nio_entry_t list_entry;
#endif

#define req_buf fnsvc_bbc_req_buf
#define resp_buf fnsvc_bbc_resp_buf
#define last_error fnsvc_bbc_last_error
#define last_status fnsvc_bbc_last_status
#define last_raw_error fnsvc_bbc_last_raw_error
#define last_response_len fnsvc_bbc_last_response_len

#ifndef CONFIG_NIO_BBC_LITE
static int fail(uint8_t error)
{
  last_error = error;
  return 0;
}

int fnsvc_config_nio_list_directory_page(config_nio_state_t *state,
                                         const char *uri, uint16_t start,
                                         uint8_t max_entries,
                                         uint16_t *next_start,
                                         uint8_t *more)
{
  uint16_t uri_len;
  uint8_t status;
  uint16_t resp_len;
  uint16_t off;
  uint16_t count;
  uint16_t entries_len;
  uint16_t pos;
  uint16_t idx;
  uint8_t delivered;
  uint8_t flags;
  uint16_t max_payload;
  uint8_t result;

  if (!state || !uri || max_entries == 0)
    return fail(FNSVC_ERR_INVALID_ARG);

  state->entry_count = 0;
  uri_len = (uint16_t) strlen(uri);
  last_error = FNSVC_ERR_NONE;
  last_status = 0;
  last_raw_error = 0;
  last_response_len = 0;
  max_payload = FNSVC_LIST_MAX_PAYLOAD;
  if (max_payload > (uint16_t) (sizeof(resp_buf) - 10))
    max_payload = (uint16_t) (sizeof(resp_buf) - 10);

  /* v1 + uriLen + startIndex + maxPayloadBytes + flags + maxNameBytes = 7 bytes. */
  if (uri_len + BBC_LIST_REQUEST_OVERHEAD > sizeof(req_buf))
    return fail(FNSVC_ERR_REQUEST_TOO_LARGE);

  off = 0;
  req_buf[off++] = NIO_FILE_VERSION;
  req_buf[off++] = (uint8_t) uri_len;
  req_buf[off++] = (uint8_t) (uri_len >> 8);
  memcpy(&req_buf[off], uri, uri_len);
  off += uri_len;
  req_buf[off++] = (uint8_t) start;
  req_buf[off++] = (uint8_t) (start >> 8);
  req_buf[off++] = (uint8_t) max_payload;
  req_buf[off++] = (uint8_t) (max_payload >> 8);
  req_buf[off++] = NIO_FILE_LIST_FLAG_SORT_BY_NAME | NIO_FILE_LIST_FLAG_COMPACT;
  req_buf[off++] = BBC_LIST_NAME_MAX;

  result = fn_bbc_device_call_raw(NIO_DEVICEID_FILE, NIO_FILE_LIST_DIRECTORY,
                                  req_buf, off, resp_buf, sizeof(resp_buf),
                                  &status, &resp_len);
  if (result != FN_OK) {
    last_raw_error = result;
    return fail(FNSVC_ERR_TRANSPORT);
  }
  last_raw_error = 0;

  last_status = status;
  last_response_len = resp_len;
  if (status != FNSVC_STATUS_OK)
    return fail(FNSVC_ERR_STATUS);
  if (resp_len < 10)
    return fail(FNSVC_ERR_SHORT_RESPONSE);
  if (resp_buf[0] != NIO_FILE_VERSION)
    return fail(FNSVC_ERR_BAD_VERSION);

  flags = resp_buf[1];
  count = (uint16_t) resp_buf[6] | ((uint16_t) resp_buf[7] << 8);
  entries_len = (uint16_t) resp_buf[8] | ((uint16_t) resp_buf[9] << 8);
  if ((uint16_t) (10 + entries_len) > resp_len)
    return fail(FNSVC_ERR_ENTRIES_BOUNDS);

  pos = 10;
  delivered = 0;
  for (idx = 0; idx < count; idx++) {
    uint8_t eflags;
    uint8_t name_len;

    if ((uint16_t) (pos + 2) > resp_len)
      return fail(FNSVC_ERR_ENTRY_BOUNDS);
    eflags = resp_buf[pos++];
    name_len = resp_buf[pos++];
    if ((uint16_t) (pos + name_len) > resp_len)
      return fail(FNSVC_ERR_ENTRY_BOUNDS);

    if (delivered < max_entries) {
      uint8_t copy_len;

      copy_len = name_len;
      if (copy_len > BBC_LIST_NAME_MAX)
        copy_len = BBC_LIST_NAME_MAX;
      list_entry.is_dir = (uint8_t) (eflags & (0x01 | NIO_FILE_LIST_ENTRY_TRUNCATED));
      memcpy(list_entry.name, &resp_buf[pos], copy_len);
      list_entry.name[copy_len] = 0;
      (void) config_nio_entry_set(state, delivered, &list_entry);
      delivered++;
    }
    pos = (uint16_t) (pos + name_len);
  }

  if (next_start)
    *next_start = (uint16_t) (start + delivered);
  if (more)
    *more = (uint8_t) (delivered < count || (flags & NIO_FILE_LIST_RESP_MORE) != 0);
  state->entry_count = delivered;
  return 1;
}
#endif

#ifndef CONFIG_NIO_BBC_LITE
int fnsvc_get_mount(uint8_t slot, fnsvc_mount_t *mount)
{
  uint8_t status;
  uint16_t resp_len;
  uint16_t off;
  uint8_t len;
  uint8_t result;

  if (!mount || slot >= FNCTL_MAX_UNITS)
    return 0;
  last_error = FNSVC_ERR_NONE;
  mount->enabled = 0;
  mount->uri[0] = 0;
  mount->mode[0] = 0;
  req_buf[0] = slot;

  result = fn_bbc_device_call_raw(NIO_DEVICEID_FUJI, NIO_FUJI_GET_MOUNT,
                                  req_buf, 1, resp_buf, sizeof(resp_buf),
                                  &status, &resp_len);
  if (result != FN_OK) {
    last_raw_error = result;
    return fail(FNSVC_ERR_TRANSPORT);
  }
  last_raw_error = 0;

  last_status = status;
  last_response_len = resp_len;
  if (status != FNSVC_STATUS_OK)
    return fail(FNSVC_ERR_STATUS);
  if (resp_len < 4 || resp_buf[0] != slot)
    return fail(FNSVC_ERR_SHORT_RESPONSE);

  mount->enabled = resp_buf[1] & 0x01;
  off = 3;
  len = resp_buf[2];
  if (off + len + 1 > resp_len)
    return fail(FNSVC_ERR_SHORT_RESPONSE);
  if (len >= sizeof(mount->uri))
    len = (uint8_t) (sizeof(mount->uri) - 1);
  memcpy(mount->uri, &resp_buf[off], len);
  mount->uri[len] = 0;
  off = (uint16_t) (off + resp_buf[2]);

  len = resp_buf[off++];
  if (off + len > resp_len)
    return fail(FNSVC_ERR_SHORT_RESPONSE);
  if (len >= sizeof(mount->mode))
    len = (uint8_t) (sizeof(mount->mode) - 1);
  memcpy(mount->mode, &resp_buf[off], len);
  mount->mode[len] = 0;
  return 1;
}
#endif

#ifndef CONFIG_NIO_BBC_LITE
int fnsvc_set_mount(uint8_t slot, const char *uri, const char *mode, uint8_t enabled)
{
  uint8_t status;
  uint16_t resp_len;
  uint8_t uri_len;
  uint8_t mode_len;
  uint16_t off;
  uint8_t result;

  if (!uri)
    uri = "";
  if (!mode)
    mode = "";
  if (slot >= FNCTL_MAX_UNITS)
    return 0;
  if (strlen(uri) > FNSVC_MOUNT_URI_MAX || strlen(mode) > 3)
    return 0;

  uri_len = (uint8_t) strlen(uri);
  mode_len = (uint8_t) strlen(mode);
  /* slot + enabled + uriLen + modeLen = 4 bytes, excluding the two strings. */
  if (uri_len + mode_len + BBC_SET_MOUNT_REQUEST_OVERHEAD > sizeof(req_buf))
    return 0;

  off = 0;
  req_buf[off++] = slot;
  req_buf[off++] = enabled ? 0x01 : 0x00;
  req_buf[off++] = uri_len;
  memcpy(&req_buf[off], uri, uri_len);
  off = (uint16_t) (off + uri_len);
  req_buf[off++] = mode_len;
  memcpy(&req_buf[off], mode, mode_len);
  off = (uint16_t) (off + mode_len);

  result = fn_bbc_device_call_raw(NIO_DEVICEID_FUJI, NIO_FUJI_SET_MOUNT,
                                  req_buf, off, resp_buf, sizeof(resp_buf),
                                  &status, &resp_len);
  if (result != FN_OK) {
    last_raw_error = result;
    return 0;
  }
  last_raw_error = 0;
  return status == FNSVC_STATUS_OK;
}
#endif

uint8_t fnsvc_last_error(void)
{
  return last_error;
}

uint8_t fnsvc_last_status(void)
{
  return last_status;
}

uint8_t fnsvc_last_raw_error(void)
{
  return last_raw_error;
}

uint16_t fnsvc_last_response_len(void)
{
  return last_response_len;
}
