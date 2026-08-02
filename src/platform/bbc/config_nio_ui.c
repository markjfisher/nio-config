#include "config_nio.h"
#include "config_nio_layout.h"

#include <bbc.h>
#include <conio.h>
#include <string.h>

#include "fn_bbc_internal.h"

// ASM implementations
extern int prompt_host(void);
extern uint8_t key_is_next_page(char key);
extern uint8_t key_is_previous_page(char key);
extern void put_slot_index(uint8_t value);
extern void config_nio_run(config_nio_state_t *state);
extern char *runtime_mount_display(uint8_t unit);
extern int fetch_browse_page(config_nio_state_t *state);
extern void draw_browse(config_nio_state_t *state);
extern void draw_drive_rows(config_nio_state_t *state);
extern int prompt_assign_slot(config_nio_state_t *state, uint8_t *slot_out);
extern int fetch_next_browse_page(config_nio_state_t *state);
extern int fetch_previous_browse_page(config_nio_state_t *state);
extern void show_hosts(config_nio_state_t *state);
extern void draw_slot_rows(config_nio_state_t *state);
extern void edit_host(config_nio_state_t *state);
extern void clear_host(config_nio_state_t *state);
extern void assign_selected_file(config_nio_state_t *state);


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

enum {
  SCREEN_HOSTS,
  SCREEN_BROWSE,
  SCREEN_SLOTS
};

extern uint8_t config_nio_store_buf[];
#define edit_buf ((char *) config_nio_store_buf)
char uri_buf[BBC_URI_WORK_MAX];
const uint8_t runtime_offsets[] = { 0, 20, 40, 60 };

/* Runtime mounts are deliberately transient: config-nio's persistent mapping
 * table contains catalogue-slot assignments, while boot/FBOOT mounts are
 * DiskService state and do not necessarily have a catalogue slot. */
extern uint8_t fnsvc_bbc_resp_buf[];

void refresh_runtime_mounts(void)
{
  uint8_t i;

  for (i = 0; i < BBC_DRIVE_COUNT; i++)
    (void) runtime_mount_display(i);
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

void mode7(void)
{
  cputc(22);
  cputc(7);
  bbc_cursor(0);
}

void clear_field(uint8_t x, uint8_t y, uint8_t width)
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

static void load_screen_template(const char *asset_name)
{
  config_nio_bbc_load_template(asset_name);
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

static void reset_browse_pages(void)
{
  browse_page_depth = 0;
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

static void set_host_marker(uint8_t host, uint8_t selected)
{
  if (host < hosts_start || host >= (uint8_t) (hosts_start + BBC_HOST_PAGE_ROWS))
    return;
  gotoxy(CONFIG_NIO_BBC_HOSTS_ROWS_X, (uint8_t) (CONFIG_NIO_BBC_HOSTS_ROWS_Y + host - hosts_start));
  cputc(selected ? '>' : ' ');
}

static void set_browse_marker(uint8_t row, uint8_t selected)
{
  gotoxy(CONFIG_NIO_BBC_BROWSE_ROWS_X, (uint8_t) (CONFIG_NIO_BBC_BROWSE_ROWS_Y + row));
  cputc(selected ? '>' : ' ');
}

void draw_slots(config_nio_state_t *state)
{
  load_screen_template("CNSLOTS");
  draw_slot_rows(state);
  draw_drive_rows(state);
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
