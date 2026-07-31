#include "config_nio.h"
#include "config_nio_layout.h"

#include <bbc.h>
#include <conio.h>
#include <string.h>

#include "fn_bbc_internal.h"

extern uint8_t label_width (const char *label);

#define BBC_WIDTH CONFIG_NIO_BBC_SCREEN_WIDTH
#define BBC_ROWS CONFIG_NIO_BBC_SCREEN_HEIGHT
#define BBC_DRIVE_COUNT 4
#define BBC_BROWSE_PAGE_ROWS CONFIG_NIO_BBC_BROWSE_ROWS_COUNT
#define BBC_HOST_PAGE_ROWS CONFIG_NIO_BBC_HOSTS_ROWS_COUNT
#define BBC_HOST_TEXT_X (CONFIG_NIO_BBC_HOSTS_ROWS_X + 4)
#define BBC_HOST_ROW_WIDTH (CONFIG_NIO_BBC_HOSTS_ROWS_URI_WIDTH + 4)
#define BBC_URI_WORK_MAX (CONFIG_NIO_URI_MAX + 1)
#define BBC_EDIT_BUF_SIZE 97
#define BBC_LIST_PAYLOAD 120
#define NIO_DEVICE_DISK 0xFC
#define NIO_DISK_LIST_MOUNTS 0x0D
#define NIO_DISK_LIST_MOUNTS_HEADER 10
#define BBC_MOUNTS_PAYLOAD 240
#define NIO_DISK_LIST_MOUNTS_RESPONSE (BBC_MOUNTS_PAYLOAD + NIO_DISK_LIST_MOUNTS_HEADER)
#define BBC_RUNTIME_NAME_WIDTH 19
#define BBC_BROWSE_PAGE_STACK 6
#define key_is_quit(key) ((key) == 'q' || (key) == 'Q' || (key) == CH_ESC)
#define key_is_up(key) ((key) == CH_CURS_UP || (key) == 'w' || (key) == 'W')
#define key_is_down(key) ((key) == CH_CURS_DOWN || (key) == 's')
#define key_is_left(key) ((key) == CH_CURS_LEFT)
#define key_is_right(key) ((key) == CH_CURS_RIGHT)
#define key_is_escape(key) ((key) == CH_ESC)

static uint8_t key_is_next_page(int key)
{
  return (uint8_t) (key_is_right(key) || key == 'n' || key == 'N' || key == '>');
}

static uint8_t key_is_previous_page(int key)
{
  return (uint8_t) (key_is_left(key) || key == 'p' || key == 'P' || key == '<');
}

enum {
  SCREEN_HOSTS,
  SCREEN_BROWSE,
  SCREEN_SLOTS
};

extern uint8_t config_nio_store_buf[];
#define edit_buf ((char *) config_nio_store_buf)
char uri_buf[BBC_URI_WORK_MAX];
static const uint8_t runtime_offsets[] = { 0, 20, 40, 60 };

/* Runtime mounts are deliberately transient: config-nio's persistent mapping
 * table contains catalogue-slot assignments, while boot/FBOOT mounts are
 * DiskService state and do not necessarily have a catalogue slot. */
extern uint8_t fnsvc_bbc_resp_buf[];
static char *runtime_mount_display(uint8_t unit)
{
  char *display;
  uint8_t request[10];
  uint8_t device_status;
  uint8_t result;
  uint16_t response_len;
  const uint8_t *start;
  const uint8_t *end;
  const uint8_t *uri;
  const uint8_t *name;
  const uint8_t *p;
  uint8_t len;

  display = &uri_buf[runtime_offsets[unit]];
  display[0] = 0;
  request[0] = 1;
  request[1] = 1;
  request[2] = unit;
  request[3] = 0;
  request[4] = unit;
  request[5] = 0;
  request[6] = 0;
  request[7] = 0;
  request[8] = (uint8_t) (BBC_MOUNTS_PAYLOAD & 0xFF);
  request[9] = (uint8_t) (BBC_MOUNTS_PAYLOAD >> 8);
  result = fn_bbc_device_call_raw(
      NIO_DEVICE_DISK, NIO_DISK_LIST_MOUNTS, request, sizeof(request),
      fnsvc_bbc_resp_buf, NIO_DISK_LIST_MOUNTS_RESPONSE, &device_status,
      &response_len);
  if (result != 0 || device_status != 0 ||
      response_len < NIO_DISK_LIST_MOUNTS_HEADER ||
      fnsvc_bbc_resp_buf[0] != 1 || (fnsvc_bbc_resp_buf[1] & 0x02) == 0 ||
      fnsvc_bbc_resp_buf[6] == 0)
    return 0;

  start = fnsvc_bbc_resp_buf + NIO_DISK_LIST_MOUNTS_HEADER;
  end = start + fnsvc_bbc_resp_buf[8];
  if (fnsvc_bbc_resp_buf[8] < 8 || start[0] != (uint8_t) ('0' + unit) ||
      start[1] != ':' || start[2] != ' ')
    return 0;
  uri = start + 3;
  while (uri < end && *uri != ' ') uri++;
  while (uri < end && *uri == ' ') uri++;
  name = uri;
  for (p = uri; p < end; p++)
    if (*p == '/' || *p == ':') name = p + 1;
  len = (uint8_t) (end - name);
  if (len > BBC_RUNTIME_NAME_WIDTH) len = BBC_RUNTIME_NAME_WIDTH;
  memcpy(display, name, len);
  display[len] = 0;
  return display;
}

static void refresh_runtime_mounts(void)
{
  uint8_t i;

  for (i = 0; i < BBC_DRIVE_COUNT; i++)
    (void) runtime_mount_display(i);
}

static void put_slot_index(uint8_t value)
{
  uint8_t hundreds = 0;
  uint8_t tens = 0;
  while (value >= 100) { value = (uint8_t) (value - 100); hundreds++; }
  while (value >= 10) { value = (uint8_t) (value - 10); tens++; }
  if (hundreds) cputc((char) ('0' + hundreds));
  if (hundreds || tens) cputc((char) ('0' + tens));
  cputc((char) ('0' + value));
}

static uint8_t slot_index_width(uint8_t value)
{
  if (value >= 100)
    return 3;
  if (value >= 10)
    return 2;
  return 1;
}

uint8_t current_screen;
uint8_t selected_host;
uint8_t selected_entry;
uint8_t selected_drive;
uint8_t selected_slot;
uint8_t assign_slot_start;
uint8_t slots_focus;
uint8_t browse_host;
uint8_t hosts_start;
uint16_t browse_start;
uint16_t browse_next;
uint16_t browse_page_stack[BBC_BROWSE_PAGE_STACK];
uint8_t browse_page_depth;
uint8_t browse_more;

void __fastcall__ config_nio_bbc_cursor(uint8_t on);
void __fastcall__ config_nio_bbc_clear_line(uint8_t row);
void config_nio_bbc_put_fixed(const char *s, uint8_t width);
void config_nio_bbc_put_tail(const char *s, uint8_t width);
void config_nio_bbc_put_basename(const char *s, uint8_t width);
extern char *config_nio_bbc_edit_buf;
extern uint8_t config_nio_bbc_edit_cap;
extern uint8_t config_nio_bbc_edit_x;
extern uint8_t config_nio_bbc_edit_y;
extern uint8_t config_nio_bbc_edit_width;
int config_nio_bbc_edit_line(void);
void config_nio_bbc_load_template(const char *asset_name);
void __fastcall__ config_nio_bbc_parent_path(char *path);
int config_nio_bbc_enter_dir(char *path, const char *name);
#define clear_line(row) config_nio_bbc_clear_line(row)
#define bbc_cursor(on) config_nio_bbc_cursor(on)
#define put_fixed(s, width) config_nio_bbc_put_fixed((s), (width))
#define put_tail(s, width) config_nio_bbc_put_tail((s), (width))
#define put_basename(s, width) config_nio_bbc_put_basename((s), (width))

static void mode7(void)
{
  cputc(22);
  cputc(7);
}

static void text_at(uint8_t x, uint8_t y, const char *s)
{
  gotoxy(x, y);
  cputs(s ? s : "");
}

static void clear_field(uint8_t x, uint8_t y, uint8_t width)
{
  gotoxy(x, y);
  put_fixed("", width);
  gotoxy(x, y);
}

static void pause_line(const char *s)
{
  (void) s;
  (void) cgetc();
}

// static uint8_t label_width(const char *label)
// {
//   uint8_t len;

//   len = 0;
//   while (label && label[len] && len < 12)
//     len++;
//   return len;
// }

static void load_screen_template(const char *asset_name)
{
  config_nio_bbc_load_template(asset_name);
}

static int prompt_line(const char *label, char *buf, uint8_t cap)
{
  uint8_t label_len;
  uint8_t width;
  uint8_t x;
  uint8_t y;
  uint8_t clear_x;
  uint8_t clear_width;
  int result;

  if (!buf || cap == 0)
    return 0;

  label_len = label_width(label ? label : "Value");
  if (current_screen == SCREEN_BROWSE) {
    x = CONFIG_NIO_BBC_BROWSE_INPUT_TEXT_X;
    y = CONFIG_NIO_BBC_BROWSE_INPUT_Y;
    clear_x = CONFIG_NIO_BBC_BROWSE_INPUT_LABEL_X;
    width = CONFIG_NIO_BBC_BROWSE_INPUT_WIDTH;
    clear_width = CONFIG_NIO_BBC_BROWSE_INPUT_CLEAR_WIDTH;
  } else {
    x = BBC_HOST_TEXT_X;
    y = (uint8_t) (CONFIG_NIO_BBC_HOSTS_ROWS_Y + selected_host - hosts_start);
    clear_x = x;
    width = CONFIG_NIO_BBC_HOSTS_ROWS_URI_WIDTH;
    clear_width = width;
  }
  if (cap <= width)
    width = (cap - 1);
  if (width == 0)
    return 0;

  clear_field(clear_x, y, clear_width);
  if (current_screen == SCREEN_BROWSE) {
    cputs(label ? label : "Value");
    cputs(":");
    if (label_len < 5)
      put_fixed("", (uint8_t) (5 - label_len));
  }
  clear_field(x, y, width);

  config_nio_bbc_edit_buf = buf;
  config_nio_bbc_edit_cap = cap;
  config_nio_bbc_edit_x = x;
  config_nio_bbc_edit_y = y;
  config_nio_bbc_edit_width = width;
  result = config_nio_bbc_edit_line();
  if (current_screen == SCREEN_BROWSE)
    clear_field(clear_x, y, clear_width);
  return result;
}

static void parent_path(char *path)
{
  config_nio_bbc_parent_path(path);
}

static int enter_dir(config_nio_state_t *state, const char *name)
{
  if (!config_nio_bbc_enter_dir(state->browse_path, name)) {
    config_nio_set_status(state, "Path long");
    return 0;
  }
  return 1;
}

static int fetch_browse_page(config_nio_state_t *state)
{
  uint8_t ok;
  uint16_t fetch_start;
  uint16_t next_start;
  uint8_t more;
  uint8_t remaining;

  state->entry_count = 0;
  state->entries_truncated = 0;
  if (!config_nio_host_get(state, browse_host, edit_buf, BBC_EDIT_BUF_SIZE) ||
      !config_nio_compose_uri(edit_buf, state->browse_path,
                              "", uri_buf, sizeof(uri_buf))) {
    config_nio_set_status(state, "Path long");
    return 0;
  }

  fetch_start = browse_start;
  browse_more = 0;
  browse_next = browse_start;
  do {
    remaining = (uint8_t) (BBC_BROWSE_PAGE_ROWS - state->entry_count);
  config_nio_bbc_invalidate_slot_cache();
  ok = (uint8_t) fnsvc_config_nio_list_directory_page(state, uri_buf,
                                                        fetch_start,
                                                        remaining,
                                                        &next_start,
                                                        &more);
    if (!ok) {
      config_nio_set_status(state, "Host error");
      return 0;
    }
    browse_next = next_start;
    browse_more = more;
    if (!more || next_start == fetch_start)
      break;
    fetch_start = next_start;
  } while (state->entry_count < BBC_BROWSE_PAGE_ROWS);

  selected_entry = 0;
  config_nio_set_status(state, browse_more ? "More" : "End");
  return 1;
}

static void reset_browse_pages(void)
{
  browse_page_depth = 0;
}

static int fetch_next_browse_page(config_nio_state_t *state)
{
  uint16_t old_start;

  if (!browse_more)
    return 0;
  old_start = browse_start;
  if (browse_page_depth < BBC_BROWSE_PAGE_STACK)
    browse_page_stack[browse_page_depth++] = old_start;
  browse_start = browse_next;
  if (fetch_browse_page(state))
    return 1;
  browse_start = old_start;
  if (browse_page_depth > 0)
    browse_page_depth--;
  return 0;
}

static int fetch_previous_browse_page(config_nio_state_t *state)
{
  if (browse_page_depth > 0)
    browse_start = browse_page_stack[--browse_page_depth];
  else
    browse_start = 0;
  if (fetch_browse_page(state) && state->entry_count > 0)
    selected_entry = (uint8_t) (state->entry_count - 1);
  return 1;
}

static uint8_t last_host_page_start(void)
{
#if CONFIG_NIO_MAX_HOSTS <= BBC_HOST_PAGE_ROWS
  return 0;
#else
  return (uint8_t) (((CONFIG_NIO_MAX_HOSTS - 1) / BBC_HOST_PAGE_ROWS) * BBC_HOST_PAGE_ROWS);
#endif
}

static uint8_t host_page_start(uint8_t host)
{
  uint8_t start;
  uint8_t last;

  start = (uint8_t) ((host / BBC_HOST_PAGE_ROWS) * BBC_HOST_PAGE_ROWS);
  last = last_host_page_start();
  if (start > last)
    start = last;
  return start;
}

static void show_hosts(config_nio_state_t *state)
{
  uint8_t i;
  uint8_t host;

  if (selected_host < hosts_start)
    hosts_start = host_page_start(selected_host);
  else if (selected_host >= (uint8_t) (hosts_start + BBC_HOST_PAGE_ROWS))
    hosts_start = host_page_start(selected_host);

  load_screen_template("CNHOSTS");
  for (i = 0; i < BBC_HOST_PAGE_ROWS; i++) {
    host = (uint8_t) (hosts_start + i);
    gotoxy(CONFIG_NIO_BBC_HOSTS_ROWS_X, (uint8_t) (CONFIG_NIO_BBC_HOSTS_ROWS_Y + i));
    if (host >= CONFIG_NIO_MAX_HOSTS) {
      put_fixed("", BBC_HOST_ROW_WIDTH);
      continue;
    }
    cputc(host == selected_host ? '>' : ' ');
    if (host >= 10)
      cputc('1');
    else
      cputc(' ');
    cputc((char) ('0' + (host % 10)));
    cputc(' ');
    if (host < state->host_count && config_nio_host_get(state, host, edit_buf, BBC_EDIT_BUF_SIZE))
      put_tail(edit_buf, CONFIG_NIO_BBC_HOSTS_ROWS_URI_WIDTH);
    else
      put_fixed("", CONFIG_NIO_BBC_HOSTS_ROWS_URI_WIDTH);
  }
}

static void set_host_marker(uint8_t host, uint8_t selected)
{
  if (host < hosts_start || host >= (uint8_t) (hosts_start + BBC_HOST_PAGE_ROWS))
    return;
  gotoxy(CONFIG_NIO_BBC_HOSTS_ROWS_X, (uint8_t) (CONFIG_NIO_BBC_HOSTS_ROWS_Y + host - hosts_start));
  cputc(selected ? '>' : ' ');
}

static void draw_browse(config_nio_state_t *state)
{
  uint8_t i;
  config_nio_entry_t entry;

  load_screen_template("CNBROW");
  clear_field(CONFIG_NIO_BBC_BROWSE_HOST_X, CONFIG_NIO_BBC_BROWSE_HOST_Y, CONFIG_NIO_BBC_BROWSE_HOST_WIDTH);
  if (config_nio_host_get(state, browse_host, edit_buf, BBC_EDIT_BUF_SIZE))
    put_tail(edit_buf, CONFIG_NIO_BBC_BROWSE_HOST_WIDTH);
  clear_field(CONFIG_NIO_BBC_BROWSE_PATH_X, CONFIG_NIO_BBC_BROWSE_PATH_Y, CONFIG_NIO_BBC_BROWSE_PATH_WIDTH);
  cputc('/');
  put_tail(state->browse_path, CONFIG_NIO_BBC_BROWSE_PATH_WIDTH);
  for (i = 0; i < BBC_BROWSE_PAGE_ROWS; i++) {
    gotoxy(CONFIG_NIO_BBC_BROWSE_ROWS_X, (uint8_t) (CONFIG_NIO_BBC_BROWSE_ROWS_Y + i));
    if (i < state->entry_count &&
        config_nio_entry_get(state, i, &entry)) {
      cputc(i == selected_entry ? '>' : ' ');
      cputc((entry.is_dir & CONFIG_NIO_ENTRY_FLAG_DIR) ? '/' : ' ');
      cputc(' ');
      put_tail(entry.name, CONFIG_NIO_BBC_BROWSE_ROWS_NAME_WIDTH);
    } else {
      put_fixed("", CONFIG_NIO_BBC_BROWSE_ROWS_CLEAR_WIDTH);
    }
  }
}

static void set_browse_marker(uint8_t row, uint8_t selected)
{
  gotoxy(CONFIG_NIO_BBC_BROWSE_ROWS_X, (uint8_t) (CONFIG_NIO_BBC_BROWSE_ROWS_Y + row));
  cputc(selected ? '>' : ' ');
}

static void draw_slots(config_nio_state_t *state)
{
  uint8_t i;
  char *runtime_name;
  config_nio_mapping_t mapping;
  config_nio_slot_t slot;

  load_screen_template("CNSLOTS");
  runtime_name = uri_buf;
  for (i = 0; i < FNCTL_MAX_UNITS; i++) {
    gotoxy(CONFIG_NIO_BBC_SLOTS_SLOTS_X, (uint8_t) (CONFIG_NIO_BBC_SLOTS_SLOTS_Y + i));
    cputc((slots_focus && i == selected_slot) ? '>' : ' ');
    cputc(' ');
    put_slot_index((uint8_t) (state->slot_start + i));
    cputc(' ');
    if (config_nio_slot_get(state, i, &slot))
      put_tail(slot.uri, CONFIG_NIO_BBC_SLOTS_SLOTS_URI_WIDTH);
    else
      put_fixed("", CONFIG_NIO_BBC_SLOTS_SLOTS_URI_WIDTH);
  }
  for (i = 0; i < BBC_DRIVE_COUNT; i++) {
    gotoxy(CONFIG_NIO_BBC_SLOTS_DRIVES_X, (uint8_t) (CONFIG_NIO_BBC_SLOTS_DRIVES_Y + i));
    cputc((!slots_focus && i == selected_drive) ? '>' : ' ');
    cputs("D");
    cputc((char) ('0' + i));
    cputc(' ');
    if (config_nio_mapping_get(state, i, &mapping) && mapping.valid) {
      cputs("S");
      put_slot_index(mapping.slot);
      cputc(' ');
      cputc(mapping.readonly ? 'R' : 'W');
      cputc(' ');
      if (config_nio_read_slot(mapping.slot, &slot) && slot.enabled)
        put_basename(
          slot.uri,
          (uint8_t) (CONFIG_NIO_BBC_SLOTS_DRIVES_BASENAME_WIDTH -
                     (slot_index_width(mapping.slot) - 1)));
      else
        put_fixed(
          "",
          (uint8_t) (CONFIG_NIO_BBC_SLOTS_DRIVES_BASENAME_WIDTH -
                     (slot_index_width(mapping.slot) - 1)));
    } else if (*runtime_name) {
      cputs("BOOT ");
      put_basename(runtime_name, BBC_RUNTIME_NAME_WIDTH);
    } else {
      cputs("--");
      put_fixed("", CONFIG_NIO_BBC_SLOTS_DRIVES_EMPTY_WIDTH);
    }
    runtime_name += 20;
  }
}

static void set_drive_marker(uint8_t row, uint8_t selected)
{
  gotoxy(CONFIG_NIO_BBC_SLOTS_DRIVES_X, (uint8_t) (CONFIG_NIO_BBC_SLOTS_DRIVES_Y + row));
  cputc(selected ? '>' : ' ');
}

static void set_slot_marker(uint8_t row, uint8_t selected)
{
  gotoxy(CONFIG_NIO_BBC_SLOTS_SLOTS_X, (uint8_t) (CONFIG_NIO_BBC_SLOTS_SLOTS_Y + row));
  cputc(selected ? '>' : ' ');
}

static void set_assign_marker(uint8_t row, uint8_t selected)
{
  gotoxy(CONFIG_NIO_BBC_BROWSE_ASSIGN_X, (uint8_t) (CONFIG_NIO_BBC_BROWSE_ASSIGN_ROWS_Y + row));
  cputc(selected ? '>' : ' ');
}

static void draw_assign_slots(config_nio_state_t *state, uint8_t slot)
{
  uint8_t i;
  config_nio_slot_t slot_state;

  state->slot_start = assign_slot_start;
  (void) config_nio_refresh_slots(state);
  for (i = 0; i < FNCTL_MAX_UNITS; i++) {
    clear_field(CONFIG_NIO_BBC_BROWSE_ASSIGN_X,
                (uint8_t) (CONFIG_NIO_BBC_BROWSE_ASSIGN_ROWS_Y + i),
                CONFIG_NIO_BBC_BROWSE_ASSIGN_CLEAR_WIDTH);
    cputc(i == slot ? '>' : ' ');
    cputc(' ');
    put_slot_index((uint8_t) (assign_slot_start + i));
    cputc(' ');
    if (config_nio_slot_get(state, i, &slot_state))
      put_tail(slot_state.uri, CONFIG_NIO_BBC_BROWSE_ASSIGN_URI_WIDTH);
    else
      put_fixed("", CONFIG_NIO_BBC_BROWSE_ASSIGN_URI_WIDTH);
  }
}

static int prompt_assign_slot(config_nio_state_t *state, uint8_t *slot_out)
{
  uint8_t i;
  uint8_t slot;
  uint8_t saved_slot_start;

  if (!slot_out)
    return 0;

  saved_slot_start = state->slot_start;
  for (i = 0; i < CONFIG_NIO_BBC_BROWSE_ASSIGN_CLEAR_ROWS; i++)
    clear_field(CONFIG_NIO_BBC_BROWSE_ASSIGN_X, (uint8_t) (CONFIG_NIO_BBC_BROWSE_ASSIGN_Y + i), CONFIG_NIO_BBC_BROWSE_ASSIGN_CLEAR_WIDTH);
  text_at(CONFIG_NIO_BBC_BROWSE_ASSIGN_X, CONFIG_NIO_BBC_BROWSE_ASSIGN_TITLE_Y, "Assign file to slot");
  text_at(CONFIG_NIO_BBC_BROWSE_ASSIGN_X, CONFIG_NIO_BBC_BROWSE_ASSIGN_HINT_Y, "P/N page  RET choose  ESC cancel");
  slot = selected_slot;
  draw_assign_slots(state, slot);

  for (;;) {
    int key;
    uint8_t old;

    key = cgetc();
    if (key_is_escape(key)) {
      state->slot_start = saved_slot_start;
      (void) config_nio_refresh_slots(state);
      return 0;
    }
    if (key == '\r' || key == '\n') {
      selected_slot = slot;
      *slot_out = (uint8_t) (assign_slot_start + slot);
      state->slot_start = saved_slot_start;
      return 1;
    }
    if (key >= '0' && key <= '7') {
      selected_slot = (uint8_t) (key - '0');
      *slot_out = (uint8_t) (assign_slot_start + selected_slot);
      state->slot_start = saved_slot_start;
      return 1;
    }
    if (key_is_next_page(key) && assign_slot_start < 248) {
      assign_slot_start = (uint8_t) (assign_slot_start + FNCTL_MAX_UNITS);
      draw_assign_slots(state, slot);
      continue;
    }
    if (key_is_previous_page(key) && assign_slot_start) {
      assign_slot_start = (uint8_t) (assign_slot_start - FNCTL_MAX_UNITS);
      draw_assign_slots(state, slot);
      continue;
    }
    old = slot;
    if (key_is_up(key) && slot > 0)
      slot--;
    else if (key_is_down(key) && slot + 1 < FNCTL_MAX_UNITS)
      slot++;
    if (old != slot) {
      set_assign_marker(old, 0);
      set_assign_marker(slot, 1);
    }
  }
}

static void edit_host(config_nio_state_t *state)
{
  if (selected_host >= CONFIG_NIO_MAX_HOSTS) {
    config_nio_set_status(state, "Host full");
    return;
  }
  if (selected_host < hosts_start ||
      selected_host >= (uint8_t) (hosts_start + BBC_HOST_PAGE_ROWS))
    show_hosts(state);
  if (selected_host < state->host_count)
    (void) config_nio_host_get(state, selected_host, edit_buf, BBC_EDIT_BUF_SIZE);
  else
    edit_buf[0] = 0;
  if (!prompt_line("Host", edit_buf, BBC_EDIT_BUF_SIZE) || !edit_buf[0])
    return;
  (void) config_nio_host_set(state, selected_host, edit_buf);
  if (selected_host >= state->host_count)
    state->host_count = (uint8_t) (selected_host + 1);
  (void) config_nio_save_hosts(state);
  config_nio_set_status(state, "Saved");
}

static void clear_host(config_nio_state_t *state)
{
  uint8_t i;

  if (selected_host >= state->host_count)
    return;
  for (i = selected_host; i + 1 < state->host_count; i++) {
    if (config_nio_host_get(state, (uint8_t) (i + 1), edit_buf, BBC_EDIT_BUF_SIZE))
      (void) config_nio_host_set(state, i, edit_buf);
  }
  state->host_count--;
  (void) config_nio_host_clear(state, state->host_count);
  if (selected_host >= state->host_count && selected_host > 0)
    selected_host--;
  (void) config_nio_save_hosts(state);
  config_nio_set_status(state, "Cleared");
}

static void assign_selected_file(config_nio_state_t *state)
{
  uint8_t slot;
  config_nio_entry_t entry;

  if (state->entry_count == 0 ||
      !config_nio_entry_get(state, selected_entry, &entry) ||
      (entry.is_dir & CONFIG_NIO_ENTRY_FLAG_DIR)) {
    config_nio_set_status(state, "Pick file");
    return;
  }
  if (entry.is_dir & CONFIG_NIO_ENTRY_FLAG_NAME_TRUNCATED) {
    config_nio_set_status(state, "Name too long");
    return;
  }
  if (!config_nio_host_get(state, browse_host, edit_buf, BBC_EDIT_BUF_SIZE) ||
      !config_nio_compose_uri(edit_buf, state->browse_path,
                              entry.name,
                              uri_buf, sizeof(uri_buf))) {
    config_nio_set_status(state, "URI long");
    return;
  }
  if (!prompt_assign_slot(state, &slot)) {
    config_nio_set_status(state, "Bad slot");
    return;
  }
  if (!config_nio_write_slot(state, slot, uri_buf, "rw")) {
    config_nio_set_status(state, "Save fail");
    return;
  }
  (void) config_nio_refresh_slots(state);
  config_nio_set_status(state, "Assigned");
}

static uint8_t handle_hosts(config_nio_state_t *state, int key)
{
  uint8_t old;

  old = selected_host;
  if (key_is_up(key) && selected_host > 0) {
    selected_host--;
    if (selected_host < hosts_start)
      return 1;
    else {
      set_host_marker(old, 0);
      set_host_marker(selected_host, 1);
    }
    return 0;
  } else if (key_is_down(key) && selected_host + 1 < CONFIG_NIO_MAX_HOSTS) {
    selected_host++;
    if (selected_host >= (uint8_t) (hosts_start + BBC_HOST_PAGE_ROWS))
      return 1;
    else {
      set_host_marker(old, 0);
      set_host_marker(selected_host, 1);
    }
    return 0;
  } else if (key_is_left(key) && hosts_start > 0) {
    hosts_start = 0;
    if (selected_host >= BBC_HOST_PAGE_ROWS)
      selected_host = 0;
    return 1;
  } else if (key_is_right(key) && hosts_start < last_host_page_start()) {
    hosts_start = last_host_page_start();
    if (selected_host < BBC_HOST_PAGE_ROWS)
      selected_host = hosts_start;
    return 1;
  } else if (key == 'e' || key == 'E') {
    edit_host(state);
    return 1;
  } else if (key == 'd' || key == 'D' || key == 'c' || key == 'C') {
    clear_host(state);
    return 1;
  } else if (key == '\r' || key == '\n') {
    if (selected_host < state->host_count) {
      browse_host = selected_host;
      state->browse_path[0] = 0;
      browse_start = 0;
      reset_browse_pages();
      if (fetch_browse_page(state))
        current_screen = SCREEN_BROWSE;
      else
        pause_line("Host error");
      return 1;
    }
  }
  return 0;
}

static uint8_t handle_browse(config_nio_state_t *state, int key)
{
  uint8_t old;

  if (key == 'H') {
    current_screen = SCREEN_HOSTS;
    return 1;
  }
  old = selected_entry;
  if (key_is_up(key)) {
    if (selected_entry > 0) {
      selected_entry--;
      set_browse_marker(old, 0);
      set_browse_marker(selected_entry, 1);
      return 0;
    } else if (browse_start > 0) {
      return (uint8_t) fetch_previous_browse_page(state);
    }
  } else if (key_is_down(key)) {
    if (selected_entry + 1 < state->entry_count) {
      selected_entry++;
      set_browse_marker(old, 0);
      set_browse_marker(selected_entry, 1);
      return 0;
    } else if (browse_more) {
      return (uint8_t) fetch_next_browse_page(state);
    }
  } else if (key_is_right(key) && browse_more) {
    return (uint8_t) fetch_next_browse_page(state);
  } else if (key_is_left(key) && browse_start > 0) {
    return (uint8_t) fetch_previous_browse_page(state);
  } else if (key == 'u' || key == 'U') {
    parent_path(state->browse_path);
    browse_start = 0;
    reset_browse_pages();
    (void) fetch_browse_page(state);
    return 1;
  } else if (key == 'a' || key == 'A') {
    assign_selected_file(state);
    return 1;
  } else if ((key == '\r' || key == '\n') && state->entry_count > 0) {
    config_nio_entry_t entry;

    if (config_nio_entry_get(state, selected_entry, &entry) &&
        (entry.is_dir & CONFIG_NIO_ENTRY_FLAG_DIR)) {
      if (entry.is_dir & CONFIG_NIO_ENTRY_FLAG_NAME_TRUNCATED) {
        config_nio_set_status(state, "Name too long");
        return 1;
      }
      if (enter_dir(state, entry.name)) {
        browse_start = 0;
        reset_browse_pages();
        (void) fetch_browse_page(state);
      }
    } else {
      assign_selected_file(state);
    }
    return 1;
  }
  return 0;
}

static uint8_t handle_slots(config_nio_state_t *state, int key)
{
  uint8_t old;
  config_nio_mapping_t mapping;

  if (key == '	') {
    if (slots_focus)
      set_slot_marker(selected_slot, 0);
    else
      set_drive_marker(selected_drive, 0);
    slots_focus = (uint8_t) !slots_focus;
    if (slots_focus)
      set_slot_marker(selected_slot, 1);
    else
      set_drive_marker(selected_drive, 1);
    return 0;
  }
  if (slots_focus) {
    if (key_is_next_page(key) && state->slots_more) {
      state->slot_start = (uint8_t) (state->slot_start + FNCTL_MAX_UNITS);
      (void) config_nio_refresh_slots(state);
      return 1;
    } else if (key_is_previous_page(key) && state->slot_start) {
      state->slot_start = state->slot_start >= FNCTL_MAX_UNITS
                        ? (uint8_t) (state->slot_start - FNCTL_MAX_UNITS) : 0;
      (void) config_nio_refresh_slots(state);
      return 1;
    }
    if (key_is_up(key) && selected_slot > 0) {
      old = selected_slot;
      selected_slot--;
      set_slot_marker(old, 0);
      set_slot_marker(selected_slot, 1);
      return 0;
    } else if (key_is_down(key) && selected_slot + 1 < FNCTL_MAX_UNITS) {
      old = selected_slot;
      selected_slot++;
      set_slot_marker(old, 0);
      set_slot_marker(selected_slot, 1);
      return 0;
    } else if (key >= '0' && key < '0' + BBC_DRIVE_COUNT) {
      uint8_t unit = (uint8_t) (key - '0');

      mapping.valid = 1;
      mapping.slot = (uint8_t) (state->slot_start + selected_slot);
      mapping.readonly = 0;
      (void) config_nio_mapping_set(state, unit, &mapping);
      (void) config_nio_save_mappings(state);
      selected_drive = unit;
      config_nio_set_status(state, "Map saved");
      return 1;
    } else if (key == 'c' || key == 'C') {
      uint8_t unit;

      uint8_t absolute = (uint8_t) (state->slot_start + selected_slot);
      if (!config_nio_delete_slot(state, absolute)) {
        config_nio_set_status(state, "Clear fail");
        return 1;
      }
      for (unit = 0; unit < FNCTL_MAX_UNITS; unit++) {
        if (config_nio_mapping_get(state, unit, &mapping) &&
            mapping.valid && mapping.slot == absolute)
          (void) config_nio_mapping_clear(state, unit);
      }
      (void) config_nio_save_mappings(state);
      (void) config_nio_refresh_slots(state);
      config_nio_set_status(state, "Cleared");
      return 1;
    } else if (key == 'e' || key == 'E') {
      config_nio_set_status(state, "Change via Hosts");
      return 1;
    }
    return 0;
  }

  old = selected_drive;
  if (key_is_up(key) && selected_drive > 0) {
    selected_drive--;
    set_drive_marker(old, 0);
    set_drive_marker(selected_drive, 1);
    return 0;
  } else if (key_is_down(key) && selected_drive + 1 < BBC_DRIVE_COUNT) {
    selected_drive++;
    set_drive_marker(old, 0);
    set_drive_marker(selected_drive, 1);
    return 0;
  } else if (key == 'r' || key == 'R') {
    if (config_nio_mapping_get(state, selected_drive, &mapping) &&
        mapping.valid) {
      mapping.readonly = (uint8_t) !mapping.readonly;
      (void) config_nio_mapping_set(state, selected_drive, &mapping);
      (void) config_nio_save_mappings(state);
    }
    return 1;
  } else if (key == 'c' || key == 'C') {
    (void) config_nio_mapping_clear(state, selected_drive);
    (void) config_nio_save_mappings(state);
    config_nio_set_status(state, "Map clear");
    return 1;
  }
  return 0;
}

void config_nio_run(config_nio_state_t *state)
{
  int done;

  mode7();
  current_screen = SCREEN_HOSTS;
  selected_host = 0;
  hosts_start = 0;
  selected_drive = 0;
  selected_slot = 0;
  assign_slot_start = 0;
  slots_focus = 0;
  done = 0;
  show_hosts(state);

  while (!done) {
    int key;
    uint8_t redraw;

    key = cgetc();
    redraw = 0;
    if (key_is_quit(key)) {
      done = 1;
    } else if (key == 'h' || key == 'H') {
      current_screen = SCREEN_HOSTS;
      redraw = 1;
    } else if (key == 's' || key == 'S') {
      current_screen = SCREEN_SLOTS;
      /* Runtime mount responses share the slot cache response buffer.  Read
       * them once before refilling the active page; redraws must not query
       * DiskService or cached pages are destroyed. */
      config_nio_bbc_invalidate_slot_cache();
      refresh_runtime_mounts();
      (void) config_nio_refresh_slots(state);
      redraw = 1;
    } else if (key == 'm' || key == 'M') {
      (void) config_nio_mount_mappings(state);
      done = 1;
    } else if (current_screen == SCREEN_HOSTS) {
      redraw = handle_hosts(state, key);
    } else if (current_screen == SCREEN_BROWSE) {
      redraw = handle_browse(state, key);
    } else {
      redraw = handle_slots(state, key);
    }

    if (redraw && !done) {
      if (current_screen == SCREEN_HOSTS)
        show_hosts(state);
      else if (current_screen == SCREEN_BROWSE)
        draw_browse(state);
      else
        draw_slots(state);
    }
  }
  clrscr();
}
