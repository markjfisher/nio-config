#include "config_nio.h"

#include <conio.h>
#include <curses.h>
#include <ctype.h>
#include <dos.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#undef getch
#undef ungetch

#define DOS_KEY_TAB 9
#define DOS_KEY_ENTER 13
#define DOS_KEY_ESC 27
#define DOS_KEY_CTRL_A 1
#define DOS_KEY_CTRL_E 5
#define DOS_KEY_CTRL_K 11
#define DOS_KEY_CTRL_Q 17
#define DOS_KEY_BACKSPACE 8
#define DOS_KEY_DEL 127
#define DOS_SCAN_ESC 0x01
#define DOS_SCAN_Q 0x10

static char dos_drive_label[16];
static char dos_uri_edit[CONFIG_NIO_URI_MAX + 1];
static uint8_t dos_selected_slot;
static uint8_t dos_selected_unit;
static uint8_t dos_focus;
static uint8_t dos_browse_focus;

#define DOS_COLOR_BODY 1
#define DOS_COLOR_FRAME 2
#define DOS_COLOR_TITLE 3
#define DOS_COLOR_SELECT 4
#define DOS_COLOR_STATUS 5
#define DOS_COLOR_WARN 6
#define DOS_COLOR_INACTIVE 7
#define DOS_COLOR_MENU 8
#define DOS_COLOR_INACTIVE_SELECT 9
#define DOS_COLOR_TITLEBAR 10
#define DOS_COLOR_MENUBAR 11
#define DOS_COLOR_MENUHOT 12
#define DOS_COLOR_BUTTON 13
#define DOS_COLOR_BUTTON_SELECT 14

#define DOS_ANIM_FRAME_MS 100
#define DOS_ANIM_END_PAUSE 5
#define DOS_ANIM_NONE 0xff
#define DOS_ANIM_BROWSE 0
#define DOS_ANIM_SLOT 1

#define DOS_SCREEN_DASHBOARD 0
#define DOS_SCREEN_HOSTS 1
#define DOS_SCREEN_BROWSE 2
#define DOS_SCREEN_SLOTS 3
#define DOS_SCREEN_PREFS 5

#define DOS_PREF_LABEL_X 2
#define DOS_PREF_LABEL_W 18
#define DOS_PREF_VALUE_X 24
#define DOS_PREF_VALUE_W 11
#define DOS_PREF_FG_X 25
#define DOS_PREF_BG_X 37
#define DOS_PREF_COLOR_W 9
#define DOS_PREF_ROW_CLEAR_W 47
#define DOS_PREF_FIRST_Y 2
#define DOS_PREF_VISIBLE_ROWS 14
#define DOS_PREF_GROUP_NONE 0xff
#define DOS_PREF_FORMAT_TOP 0
#define DOS_PREF_FORMAT_BOTTOM 3
#define DOS_PREF_COLOR_TOP 4
#define DOS_PREF_COLOR_HEADER 5

static WINDOW *dos_main_win;
static WINDOW *dos_side_win;
static WINDOW *dos_status_win;
static uint8_t dos_screen;
static int dos_last_screen = -1;
static uint8_t dos_selected_host;
static uint8_t dos_selected_entry;
static uint8_t dos_selected_pref;
static uint8_t dos_pref_scroll;
static uint8_t dos_pref_editing;
static uint8_t dos_pref_edit_field;
static uint8_t dos_pref_saved_date;
static uint8_t dos_pref_saved_size;
static uint8_t dos_pref_saved_fg;
static uint8_t dos_pref_saved_bg;
static uint8_t dos_browser_host;
static uint8_t dos_browser_cache_valid;
static uint8_t dos_parent_cache_valid;
static uint8_t dos_parent_cache_host;
static uint8_t dos_parent_cache_count;
static uint8_t dos_parent_cache_truncated;
static uint8_t dos_parent_cache_selected;
static uint16_t dos_parent_cache_total;
static char dos_parent_cache_path[FNSVC_MAX_PATH + 1];
static config_nio_entry_t dos_parent_cache_entries[CONFIG_NIO_MAX_ENTRIES];
static uint8_t dos_anim_index;
static uint8_t dos_anim_kind;
static uint8_t dos_anim_offset;
static uint8_t dos_anim_pause;
static int8_t dos_anim_dir;
static char dos_uri_buf[FNSVC_MAX_URI + 1];
static char dos_status_buf[96];

static void dos_map_selected(config_nio_state_t *state);
static void dos_toggle_mapping_mode(config_nio_state_t *state);
static void dos_clear_mapping(config_nio_state_t *state);
static void dos_clear_slot(config_nio_state_t *state);
static void dos_edit_slot(config_nio_state_t *state);
static void dos_win_title_focus(WINDOW *win, const char *title, int active);
static void dos_set_list_attr(WINDOW *win, int selected, int active);
static void dos_draw_status(const char *help, const char *status);
static const char *dos_browse_status(config_nio_state_t *state);
static void dos_draw_pref_base(WINDOW *win, int y, uint8_t pref, const char *label);
static void dos_draw_pref_value(WINDOW *win, int y, uint8_t pref, const char *value);
static void dos_draw_pref_color_line(WINDOW *win, int y, config_nio_state_t *state,
                                     uint8_t role);
static void dos_anim_reset(void);
static void dos_anim_tick(config_nio_state_t *state);
static void dos_pref_cancel_edit(config_nio_state_t *state);
static void dos_force_full_redraw(void);
static void dos_mark_full_redraw(void);

static int dos_key_is_quit(int key)
{
  return key == 'q' || key == 'Q' || key == DOS_KEY_CTRL_Q ||
         key == DOS_SCAN_Q || key == DOS_KEY_ESC || key == DOS_SCAN_ESC ||
         key == KEY_EXIT || key == KEY_SEXIT || key == KEY_CLOSE ||
         key == KEY_CANCEL || key == KEY_ABORT || key == ALT_Q ||
         key == ALT_ESC;
}

static int dos_key_is_escape(int key)
{
  return key == DOS_KEY_ESC || key == DOS_SCAN_ESC || key == KEY_CANCEL ||
         key == ALT_ESC;
}

static void dos_print_clip(const char *s, uint8_t width)
{
  uint8_t n;

  n = 0;
  while (s && *s && n < width) {
    putchar(*s++);
    n++;
  }
  while (n < width) {
    putchar(' ');
    n++;
  }
}

static void dos_curses_print_clip(WINDOW *win, const char *s, int width)
{
  int n;

  n = 0;
  while (s && *s && n < width) {
    waddch(win, *s++);
    n++;
  }
  while (n < width) {
    waddch(win, ' ');
    n++;
  }
}

static void dos_curses_print_tail(WINDOW *win, const char *s, int width)
{
  uint16_t len;

  if (!s)
    s = "";
  len = (uint16_t) strlen(s);
  if (len <= (uint16_t) width) {
    dos_curses_print_clip(win, s, width);
    return;
  }
  if (width <= 1)
    return;
  waddch(win, '~');
  dos_curses_print_clip(win, s + len - (width - 1), width - 1);
}

static void dos_clear_window(WINDOW *win, int color_pair)
{
  wbkgd(win, COLOR_PAIR(color_pair));
  wattrset(win, COLOR_PAIR(color_pair));
  wclear(win);
}

static void dos_curses_print_slice(WINDOW *win, const char *s, int width,
                                   uint8_t offset)
{
  uint16_t len;
  int n;

  if (!s)
    s = "";
  len = (uint16_t) strlen(s);
  n = 0;
  while (n < width) {
    if ((uint16_t) (offset + n) < len)
      waddch(win, s[offset + n]);
    else
      waddch(win, ' ');
    n++;
  }
}

static void dos_format_size_commas(char *out, uint32_t size)
{
  char plain[11];
  char tmp[16];
  uint8_t len;
  uint8_t commas;
  uint8_t src;
  uint8_t dst;
  uint8_t digits;

  sprintf(plain, "%lu", (unsigned long) size);
  len = (uint8_t) strlen(plain);
  commas = (uint8_t) ((len > 0) ? ((len - 1) / 3) : 0);
  src = len;
  dst = (uint8_t) (len + commas);
  tmp[dst] = 0;
  digits = 0;
  while (src > 0 && dst > 0) {
    if (digits == 3) {
      tmp[--dst] = ',';
      digits = 0;
    } else {
      tmp[--dst] = plain[--src];
      digits++;
    }
  }
  sprintf(out, "%13s", tmp);
}

static void dos_format_size_compact(char *out, uint32_t size)
{
  static const char *suffix[] = { "", "Kb", "Mb", "Gb" };
  unsigned unit;
  unsigned long divisor;
  unsigned long rem;
  unsigned whole;
  unsigned tenths;

  unit = 0;
  divisor = 1UL;
  while (size / divisor >= 1000UL && unit < 3) {
    divisor *= 1024UL;
    unit++;
  }
  if (unit == 0) {
    sprintf(out, "%13lu", (unsigned long) size);
    return;
  }
  whole = (unsigned) (size / divisor);
  rem = size % divisor;
  while (rem > 429496729UL && divisor > 1UL) {
    rem = (rem + 5UL) / 10UL;
    divisor = (divisor + 5UL) / 10UL;
  }
  tenths = (unsigned) ((rem * 10UL + (divisor / 2UL)) / divisor);
  if (tenths >= 10) {
    whole++;
    tenths = 0;
  }
  if (whole < 10 && tenths != 0)
    sprintf(out, "%9u.%u%s", whole, tenths, suffix[unit]);
  else
    sprintf(out, "%11u%s", whole, suffix[unit]);
}

static void dos_format_entry_date(config_nio_state_t *state, char *out, uint32_t mtime)
{
  time_t t;
  struct tm *tmv;

  if (mtime == 0) {
    sprintf(out, "%c%c-%c%c-%c%c", '?', '?', '?', '?', '?', '?');
    return;
  }

  t = (time_t) mtime;
  tmv = localtime(&t);
  if (!tmv) {
    sprintf(out, "%c%c-%c%c-%c%c", '?', '?', '?', '?', '?', '?');
    return;
  }
  if (state->prefs.date_format == CONFIG_NIO_PREF_DATE_YDM) {
    sprintf(out, "%02u-%02u-%02u",
            (unsigned) ((tmv->tm_year + 1900) % 100),
            (unsigned) tmv->tm_mday,
            (unsigned) (tmv->tm_mon + 1));
  } else {
    sprintf(out, "%02u-%02u-%02u",
            (unsigned) ((tmv->tm_year + 1900) % 100),
            (unsigned) (tmv->tm_mon + 1),
            (unsigned) tmv->tm_mday);
  }
}

static void dos_draw_browser_entry(config_nio_state_t *state, uint8_t index,
                                   uint8_t row)
{
  config_nio_entry_t *entry;
  char size_buf[14];
  char date_buf[9];
  uint8_t name_width;
  uint8_t offset;

  entry = &state->entries[index];
  dos_set_list_attr(dos_main_win, index == dos_selected_entry,
                    dos_browse_focus == 0);
  wmove(dos_main_win, (int) row + 3, 2);
  dos_format_entry_date(state, date_buf, entry->mtime);
  waddnstr(dos_main_win, date_buf, 8);
  waddch(dos_main_win, ' ');
  name_width = 24;
  if (index == dos_selected_entry && strlen(entry->name) > name_width) {
    offset = dos_anim_offset;
    if (dos_anim_kind != DOS_ANIM_BROWSE || dos_anim_index != dos_selected_entry)
      offset = (uint8_t) (strlen(entry->name) - name_width);
    dos_curses_print_slice(dos_main_win, entry->name, name_width, offset);
  } else {
    dos_curses_print_tail(dos_main_win, entry->name, name_width);
  }
  waddch(dos_main_win, ' ');
  if (entry->is_dir & CONFIG_NIO_ENTRY_FLAG_DIR)
    sprintf(size_buf, "%13s", "<DIR>");
  else if (state->prefs.size_format == CONFIG_NIO_PREF_SIZE_COMPACT)
    dos_format_size_compact(size_buf, entry->size);
  else
    dos_format_size_commas(size_buf, entry->size);
  waddnstr(dos_main_win, size_buf, 13);
}

static void dos_draw_input(WINDOW *win, int y, int x, int width,
                           const char *buf, uint16_t cursor, uint16_t scroll)
{
  uint16_t len;
  int i;

  if (!buf)
    buf = "";
  len = (uint16_t) strlen(buf);
  wattrset(win, COLOR_PAIR(DOS_COLOR_BODY));
  mvwaddch(win, y, x - 1, '[');
  for (i = 0; i < width; i++) {
    uint16_t pos;

    pos = (uint16_t) (scroll + i);
    if (pos < len)
      waddch(win, buf[pos]);
    else
      waddch(win, ' ');
  }
  waddch(win, ']');
  wmove(win, y, x + (int) (cursor - scroll));
}

static int dos_curses_prompt(const char *title, const char *label,
                             char *buf, uint16_t cap)
{
  uint16_t len;
  uint16_t cursor;
  uint16_t scroll;
  int width;
  int key;
  int result;
  int x;
  int y;
  int w;
  int h;
  int row;

  if (!buf || cap == 0)
    return 0;
  len = (uint16_t) strlen(buf);
  if (len >= cap) {
    len = (uint16_t) (cap - 1);
    buf[len] = 0;
  }
  cursor = len;
  scroll = 0;
  width = 56;
  x = 8;
  y = 8;
  w = 64;
  h = 7;
  timeout(-1);
  wtimeout(stdscr, -1);
  curs_set(1);

  for (;;) {
    if (cursor < scroll)
      scroll = cursor;
    while (cursor >= (uint16_t) (scroll + width))
      scroll++;

    attrset(COLOR_PAIR(DOS_COLOR_STATUS));
    for (row = 0; row < h; row++) {
      move(y + row, x);
      dos_curses_print_clip(stdscr, "", w);
    }
    mvhline(y, x + 1, ACS_HLINE, w - 2);
    mvhline(y + h - 1, x + 1, ACS_HLINE, w - 2);
    mvvline(y + 1, x, ACS_VLINE, h - 2);
    mvvline(y + 1, x + w - 1, ACS_VLINE, h - 2);
    mvaddch(y, x, ACS_ULCORNER);
    mvaddch(y, x + w - 1, ACS_URCORNER);
    mvaddch(y + h - 1, x, ACS_LLCORNER);
    mvaddch(y + h - 1, x + w - 1, ACS_LRCORNER);
    mvaddnstr(y, x + 2, title ? title : " Edit ", w - 4);
    mvaddnstr(y + 2, x + 2, label ? label : "Value", 18);
    mvaddstr(y + 5, x + 2, "Enter accept  Esc cancel  Ctrl-A/E/K edit");
    dos_draw_input(stdscr, y + 3, x + 3, width, buf, cursor, scroll);
    refresh();

    key = wgetch(stdscr);
    if (key == DOS_KEY_ESC) {
      result = 0;
      break;
    }
    if (key == DOS_KEY_ENTER || key == '\n' || key == '\r') {
      result = buf[0] != 0;
      break;
    }
    if (key == DOS_KEY_CTRL_A || key == KEY_HOME) {
      cursor = 0;
      continue;
    }
    if (key == DOS_KEY_CTRL_E || key == KEY_END) {
      cursor = len;
      continue;
    }
    if (key == DOS_KEY_CTRL_K) {
      buf[cursor] = 0;
      len = cursor;
      continue;
    }
    if (key == KEY_LEFT) {
      if (cursor > 0)
        cursor--;
      continue;
    }
    if (key == KEY_RIGHT) {
      if (cursor < len)
        cursor++;
      continue;
    }
    if (key == KEY_BACKSPACE || key == DOS_KEY_BACKSPACE || key == DOS_KEY_DEL) {
      if (cursor > 0) {
        memmove(&buf[cursor - 1], &buf[cursor], len - cursor + 1);
        cursor--;
        len--;
      }
      continue;
    }
    if (key == KEY_DC) {
      if (cursor < len) {
        memmove(&buf[cursor], &buf[cursor + 1], len - cursor);
        len--;
      }
      continue;
    }
    if (key >= 32 && key <= 126 && len + 1 < cap) {
      memmove(&buf[cursor + 1], &buf[cursor], len - cursor + 1);
      buf[cursor] = (char) key;
      cursor++;
      len++;
      continue;
    }
  }

  curs_set(0);
  dos_mark_full_redraw();
  return result;
}

static int dos_confirm_quit(void)
{
  int key;
  int selected;
  int result;
  int x;
  int y;
  int w;
  int h;
  int row;

  x = 19;
  y = 8;
  w = 42;
  h = 7;
  timeout(-1);
  wtimeout(stdscr, -1);
  flushinp();
  selected = 1;
  result = 0;

  for (;;) {
    attrset(COLOR_PAIR(DOS_COLOR_STATUS));
    for (row = 0; row < h; row++) {
      move(y + row, x);
      dos_curses_print_clip(stdscr, "", w);
    }
    mvhline(y, x + 1, ACS_HLINE, w - 2);
    mvhline(y + h - 1, x + 1, ACS_HLINE, w - 2);
    mvvline(y + 1, x, ACS_VLINE, h - 2);
    mvvline(y + 1, x + w - 1, ACS_VLINE, h - 2);
    mvaddch(y, x, ACS_ULCORNER);
    mvaddch(y, x + w - 1, ACS_URCORNER);
    mvaddch(y + h - 1, x, ACS_LLCORNER);
    mvaddch(y + h - 1, x + w - 1, ACS_LRCORNER);
    mvaddnstr(y, x + 2, " Confirmation ", w - 4);
    mvaddstr(y + 2, x + 4, "Quit CONFIG NIO?");
    attrset(selected == 0 ? COLOR_PAIR(DOS_COLOR_BUTTON_SELECT) :
             COLOR_PAIR(DOS_COLOR_BUTTON));
    mvaddstr(y + 4, x + 9, " < Ok > ");
    attrset(selected == 1 ? COLOR_PAIR(DOS_COLOR_BUTTON_SELECT) :
             COLOR_PAIR(DOS_COLOR_BUTTON));
    mvaddstr(y + 4, x + 21, " < Cancel > ");
    attrset(COLOR_PAIR(DOS_COLOR_STATUS));
    refresh();

    key = wgetch(stdscr);
    if (dos_key_is_escape(key) || key == 'c' || key == 'C') {
      result = 0;
      break;
    }
    if (key == 'o' || key == 'O') {
      result = 1;
      break;
    }
    if (key == DOS_KEY_TAB || key == KEY_LEFT || key == KEY_RIGHT) {
      selected = !selected;
      continue;
    }
    if (key == DOS_KEY_ENTER || key == '\n' || key == '\r') {
      result = selected == 0;
      break;
    }
  }

  timeout(DOS_ANIM_FRAME_MS);
  wtimeout(stdscr, DOS_ANIM_FRAME_MS);
  dos_force_full_redraw();
  return result;
}

static void dos_message_ok(const char *title, const char *message)
{
  int key;
  int x;
  int y;
  int w;
  int h;
  int row;

  x = 19;
  y = 8;
  w = 42;
  h = 7;
  timeout(-1);
  wtimeout(stdscr, -1);
  flushinp();

  for (;;) {
    attrset(COLOR_PAIR(DOS_COLOR_STATUS));
    for (row = 0; row < h; row++) {
      move(y + row, x);
      dos_curses_print_clip(stdscr, "", w);
    }
    mvhline(y, x + 1, ACS_HLINE, w - 2);
    mvhline(y + h - 1, x + 1, ACS_HLINE, w - 2);
    mvvline(y + 1, x, ACS_VLINE, h - 2);
    mvvline(y + 1, x + w - 1, ACS_VLINE, h - 2);
    mvaddch(y, x, ACS_ULCORNER);
    mvaddch(y, x + w - 1, ACS_URCORNER);
    mvaddch(y + h - 1, x, ACS_LLCORNER);
    mvaddch(y + h - 1, x + w - 1, ACS_LRCORNER);
    mvaddnstr(y, x + 2, title ? title : " Message ", w - 4);
    mvaddnstr(y + 2, x + 4, message ? message : "", w - 8);
    attrset(COLOR_PAIR(DOS_COLOR_BUTTON_SELECT));
    mvaddstr(y + 4, x + 17, " < Ok > ");
    attrset(COLOR_PAIR(DOS_COLOR_STATUS));
    refresh();

    key = wgetch(stdscr);
    if (key == DOS_KEY_ENTER || key == '\n' || key == '\r' ||
        dos_key_is_escape(key) || key == 'o' || key == 'O')
      break;
  }

  timeout(DOS_ANIM_FRAME_MS);
  wtimeout(stdscr, DOS_ANIM_FRAME_MS);
  dos_mark_full_redraw();
}

static short dos_pref_color(uint8_t value)
{
  switch (value & 7) {
  case 0:
    return COLOR_BLACK;
  case 1:
    return COLOR_BLUE;
  case 2:
    return COLOR_GREEN;
  case 3:
    return COLOR_CYAN;
  case 4:
    return COLOR_RED;
  case 5:
    return COLOR_MAGENTA;
  case 6:
    return COLOR_YELLOW;
  default:
    return COLOR_WHITE;
  }
}

static void dos_init_colors(const config_nio_prefs_t *prefs)
{
  if (!has_colors())
    return;
  start_color();
  init_pair(DOS_COLOR_BODY, dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_BODY]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_BODY]));
  init_pair(DOS_COLOR_FRAME, dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_FRAME]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_FRAME]));
  init_pair(DOS_COLOR_TITLE, dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_TITLE]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_TITLE]));
  init_pair(DOS_COLOR_SELECT, dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_SELECT]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_SELECT]));
  init_pair(DOS_COLOR_STATUS, dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_STATUS]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_STATUS]));
  init_pair(DOS_COLOR_WARN, COLOR_YELLOW, COLOR_RED);
  init_pair(DOS_COLOR_INACTIVE,
            dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_INACTIVE]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_INACTIVE]));
  init_pair(DOS_COLOR_MENU,
            dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_MENUBAR]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_MENUBAR]));
  init_pair(DOS_COLOR_INACTIVE_SELECT,
            dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_INACTIVE_SELECT]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_INACTIVE_SELECT]));
  init_pair(DOS_COLOR_TITLEBAR,
            dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_TITLEBAR]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_TITLEBAR]));
  init_pair(DOS_COLOR_MENUBAR,
            dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_MENUBAR]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_MENUBAR]));
  init_pair(DOS_COLOR_MENUHOT,
            dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_MENUHOT]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_MENUHOT]));
  init_pair(DOS_COLOR_BUTTON,
            dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_BUTTON]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_BUTTON]));
  init_pair(DOS_COLOR_BUTTON_SELECT,
            dos_pref_color(prefs->color_fg[CONFIG_NIO_COLOR_BUTTON_SELECT]),
            dos_pref_color(prefs->color_bg[CONFIG_NIO_COLOR_BUTTON_SELECT]));
}

static int dos_curses_start(config_nio_state_t *state)
{
  initscr();
  dos_init_colors(&state->prefs);
  cbreak();
  noecho();
  keypad(stdscr, TRUE);
  timeout(DOS_ANIM_FRAME_MS);
  curs_set(0);
  bkgd(COLOR_PAIR(DOS_COLOR_BODY));
  return 1;
}

static void dos_curses_stop(void)
{
  union REGS regs;

  if (dos_main_win) {
    delwin(dos_main_win);
    dos_main_win = NULL;
  }
  if (dos_side_win) {
    delwin(dos_side_win);
    dos_side_win = NULL;
  }
  if (dos_status_win) {
    delwin(dos_status_win);
    dos_status_win = NULL;
  }
  endwin();
  regs.h.ah = 0x00;
  regs.h.al = 0x03;
  int86(0x10, &regs, &regs);
}

static void dos_app_create_windows(void)
{
  if (!dos_main_win)
    dos_main_win = newwin(17, 51, 2, 1);
  if (!dos_side_win)
    dos_side_win = newwin(17, 26, 2, 53);
  if (!dos_status_win)
    dos_status_win = newwin(5, 78, 19, 1);
  keypad(dos_main_win, TRUE);
  keypad(dos_side_win, TRUE);
  keypad(dos_status_win, TRUE);
}

static void dos_win_title(WINDOW *win, const char *title)
{
  dos_win_title_focus(win, title, 1);
}

static void dos_win_title_focus(WINDOW *win, const char *title, int active)
{
  wattrset(win, COLOR_PAIR(active ? DOS_COLOR_FRAME : DOS_COLOR_INACTIVE));
  if (active)
    wattron(win, A_BOLD);
  box(win, 0, 0);
  if (active)
    wattroff(win, A_BOLD);
  wattrset(win, COLOR_PAIR(active ? DOS_COLOR_TITLE : DOS_COLOR_INACTIVE));
  mvwaddnstr(win, 0, 2, title, 22);
}

static void dos_fill_row(int y, int color_pair)
{
  int x;

  attrset(COLOR_PAIR(color_pair));
  move(y, 0);
  for (x = 0; x < 80; x++)
    addch(' ');
}

static void dos_draw_menu(void)
{
  int x;

  dos_fill_row(1, DOS_COLOR_MENUBAR);
  x = 2;
#define MENU_ITEM(hot, rest) \
  do { \
    attrset(COLOR_PAIR(DOS_COLOR_MENUHOT)); \
    mvaddch(1, x++, (hot)); \
    attrset(COLOR_PAIR(DOS_COLOR_MENUBAR)); \
    mvaddstr(1, x, (rest)); \
    x += (int) strlen(rest); \
    mvaddstr(1, x, "  "); \
    x += 2; \
  } while (0)
  MENU_ITEM('H', "osts");
  MENU_ITEM('S', "lots");
  MENU_ITEM('P', "refs");
  attrset(COLOR_PAIR(DOS_COLOR_MENUBAR));
  mvaddstr(1, x, "Mount+E");
  x += 7;
  attrset(COLOR_PAIR(DOS_COLOR_MENUHOT));
  mvaddch(1, x++, 'x');
  attrset(COLOR_PAIR(DOS_COLOR_MENUBAR));
  mvaddstr(1, x, "it  ");
  x += 4;
  MENU_ITEM('Q', "uit");
#undef MENU_ITEM
  wnoutrefresh(stdscr);
}

static const char *dos_screen_label(void)
{
  if (dos_screen == DOS_SCREEN_HOSTS)
    return "Hosts";
  if (dos_screen == DOS_SCREEN_BROWSE)
    return "Browse";
  if (dos_screen == DOS_SCREEN_SLOTS)
    return "Slots";
  if (dos_screen == DOS_SCREEN_PREFS)
    return "Preferences";
  return "Slots";
}

static void dos_draw_titlebar(void)
{
  char title[48];
  int x;

  sprintf(title, "CONFIG NIO v1.0.0 - %s", dos_screen_label());
  x = (80 - (int) strlen(title)) / 2;
  if (x < 0)
    x = 0;
  dos_fill_row(0, DOS_COLOR_TITLEBAR);
  mvaddnstr(0, x, title, 79);
  wnoutrefresh(stdscr);
}

static void dos_draw_status(const char *help, const char *status)
{
  dos_clear_window(dos_status_win, DOS_COLOR_STATUS);
  box(dos_status_win, 0, 0);
  wmove(dos_status_win, 1, 2);
  dos_curses_print_clip(dos_status_win, help ? help : "", 74);
  wmove(dos_status_win, 2, 2);
  dos_curses_print_clip(dos_status_win, status ? status : "", 74);
  wnoutrefresh(dos_status_win);
}

static const char *dos_browse_status(config_nio_state_t *state)
{
  const char *pane;

  pane = dos_browse_focus ? "Slots pane active" : "Browse pane active";
  if (!state)
    return pane;
  sprintf(dos_status_buf, "%s, %u of %u entries%s",
          pane, (unsigned) state->entry_count, (unsigned) state->entry_total,
          state->entries_truncated ? " shown" : "");
  return dos_status_buf;
}

static const char *dos_slot_status(config_nio_state_t *state)
{
  sprintf(dos_status_buf, "%s pane active, slot %u, drive %u",
          dos_focus ? "Drives" : "Slots",
          (unsigned) dos_selected_slot, (unsigned) dos_selected_unit);
  return dos_status_buf;
}

static void dos_set_list_attr(WINDOW *win, int selected, int active)
{
  if (selected && active)
    wattrset(win, COLOR_PAIR(DOS_COLOR_SELECT));
  else if (selected)
    wattrset(win, COLOR_PAIR(DOS_COLOR_INACTIVE_SELECT));
  else
    wattrset(win, COLOR_PAIR(DOS_COLOR_BODY));
}

static void dos_draw_slot_line(WINDOW *win, int y, uint8_t slot,
                               const config_nio_slot_t *mount, int selected,
                               int active, int animate)
{
  uint8_t uri_width;
  uint8_t offset;

  dos_set_list_attr(win, selected, active);
  mvwprintw(win, y, 2, "%u ", (unsigned) slot);
  uri_width = 44;
  if (mount->enabled && mount->uri[0]) {
    if (animate && selected && strlen(mount->uri) > uri_width) {
      offset = dos_anim_offset;
      if (dos_anim_kind != DOS_ANIM_SLOT || dos_anim_index != slot)
        offset = (uint8_t) (strlen(mount->uri) - uri_width);
      dos_curses_print_slice(win, mount->uri, uri_width, offset);
    } else {
      dos_curses_print_tail(win, mount->uri, uri_width);
    }
  } else {
    dos_curses_print_clip(win, "(empty)", uri_width);
  }
}

static void dos_draw_mapping_line(WINDOW *win, int y, config_nio_state_t *state,
                                  uint8_t unit, int selected, int active)
{
  config_nio_mapping_t *mapping;

  mapping = &state->mappings[unit];
  config_nio_ui_drive_label(unit, dos_drive_label, sizeof(dos_drive_label));
  dos_set_list_attr(win, selected, active);
  mvwaddnstr(win, y, 2, dos_drive_label, 5);
  if (mapping->valid) {
    wprintw(win, "->%u %s ", (unsigned) mapping->slot,
            mapping->readonly ? "ro" : "rw");
    if (mapping->slot < FNCTL_MAX_UNITS && state->slots[mapping->slot].uri[0])
      dos_curses_print_tail(win, state->slots[mapping->slot].uri, 12);
    else
      dos_curses_print_clip(win, "(empty)", 12);
  } else {
    dos_curses_print_clip(win, "(unassigned)", 17);
  }
}

static void dos_draw_side_mappings(config_nio_state_t *state)
{
  uint8_t i;

  dos_clear_window(dos_side_win, DOS_COLOR_BODY);
  dos_win_title_focus(dos_side_win, " Drives ", dos_focus == 1);
  for (i = 0; i < FNCTL_MAX_UNITS; i++)
    dos_draw_mapping_line(dos_side_win, (int) i + 2, state, i,
                          dos_selected_unit == i, dos_focus == 1);
  wattrset(dos_side_win, COLOR_PAIR(DOS_COLOR_TITLE));
  mvwaddstr(dos_side_win, 11, 2, "Actions");
  wattrset(dos_side_win, COLOR_PAIR(DOS_COLOR_BODY));
  if (dos_focus == 1) {
    mvwaddstr(dos_side_win, 12, 2, "Enter assign slot");
    mvwaddstr(dos_side_win, 13, 2, "0-7 quick assign");
    mvwaddstr(dos_side_win, 14, 2, "C clear  R ro/rw");
  } else {
    mvwaddstr(dos_side_win, 12, 2, "Tab focus drives");
    mvwaddstr(dos_side_win, 13, 2, "E edit slot");
    mvwaddstr(dos_side_win, 14, 2, "C clear slot");
    mvwaddstr(dos_side_win, 15, 2, "Enter assign");
  }
  wnoutrefresh(dos_side_win);
}

static void dos_draw_hosts(config_nio_state_t *state)
{
  uint8_t i;

  dos_clear_window(dos_main_win, DOS_COLOR_BODY);
  dos_win_title_focus(dos_main_win, " Hosts ", 1);
  for (i = 0; i < state->host_count; i++) {
    wattrset(dos_main_win, i == dos_selected_host ? COLOR_PAIR(DOS_COLOR_SELECT) : COLOR_PAIR(DOS_COLOR_BODY));
    mvwprintw(dos_main_win, (int) i + 2, 2, "%u ", (unsigned) i);
    dos_curses_print_tail(dos_main_win, state->hosts[i], 43);
  }
  if (state->host_count == 0) {
    wattrset(dos_main_win, COLOR_PAIR(DOS_COLOR_BODY));
    mvwaddstr(dos_main_win, 2, 2, "No hosts");
  }
  wnoutrefresh(dos_main_win);

  dos_clear_window(dos_side_win, DOS_COLOR_BODY);
  dos_win_title_focus(dos_side_win, " Commands ", 0);
  wattrset(dos_side_win, COLOR_PAIR(DOS_COLOR_BODY));
  mvwaddstr(dos_side_win, 2, 2, "Enter Browse");
  mvwaddstr(dos_side_win, 3, 2, "A Add");
  mvwaddstr(dos_side_win, 4, 2, "E Edit");
  mvwaddstr(dos_side_win, 5, 2, "D Delete host");
  mvwaddstr(dos_side_win, 6, 2, "+/- Reorder");
  wnoutrefresh(dos_side_win);

  dos_draw_status("Hosts: arrows move selection, Enter opens Browse",
                  state->host_count ? state->hosts[dos_selected_host] : "No hosts");
}

static void dos_draw_slots_screen(config_nio_state_t *state)
{
  uint8_t i;

  dos_clear_window(dos_main_win, DOS_COLOR_BODY);
  dos_win_title_focus(dos_main_win, " Slots ", dos_focus == 0);
  for (i = 0; i < FNCTL_MAX_UNITS; i++)
    dos_draw_slot_line(dos_main_win, (int) i + 2, i, &state->slots[i],
                       dos_selected_slot == i, dos_focus == 0, 1);
  wnoutrefresh(dos_main_win);

  dos_draw_side_mappings(state);
  dos_draw_status("Slots: Tab switches pane, E edits slot, Enter assigns slot to drive",
                  dos_slot_status(state));
}

static const char *dos_pref_color_name(uint8_t value)
{
  switch (value & 7) {
  case 0:
    return "Black";
  case 1:
    return "Blue";
  case 2:
    return "Green";
  case 3:
    return "Cyan";
  case 4:
    return "Red";
  case 5:
    return "Magenta";
  case 6:
    return "Yellow";
  default:
    return "White";
  }
}

static const char *dos_pref_role_name(uint8_t role)
{
  switch (role) {
  case CONFIG_NIO_COLOR_BODY:
    return "Body";
  case CONFIG_NIO_COLOR_FRAME:
    return "Frame";
  case CONFIG_NIO_COLOR_TITLE:
    return "Window label";
  case CONFIG_NIO_COLOR_SELECT:
    return "Selection";
  case CONFIG_NIO_COLOR_STATUS:
    return "Status";
  case CONFIG_NIO_COLOR_INACTIVE:
    return "Inactive";
  case CONFIG_NIO_COLOR_INACTIVE_SELECT:
    return "Inactive selection";
  case CONFIG_NIO_COLOR_MENUBAR:
    return "Menu";
  case CONFIG_NIO_COLOR_MENUHOT:
    return "Menu hotkey";
  case CONFIG_NIO_COLOR_TITLEBAR:
    return "Title bar";
  case CONFIG_NIO_COLOR_BUTTON:
    return "Button";
  case CONFIG_NIO_COLOR_BUTTON_SELECT:
    return "Button select";
  default:
    return "Color";
  }
}

static const char *dos_pref_description(void)
{
  if (dos_selected_pref == 0)
    return "Date format: controls file browser dates.";
  if (dos_selected_pref == 1)
    return "Size format: full uses commas, compact uses Kb/Mb/Gb.";
  switch ((uint8_t) (dos_selected_pref - 2)) {
  case CONFIG_NIO_COLOR_BODY:
    return "Body: main window text and empty-space background.";
  case CONFIG_NIO_COLOR_FRAME:
    return "Frame: active window borders.";
  case CONFIG_NIO_COLOR_TITLE:
    return "Window label: text embedded in window borders.";
  case CONFIG_NIO_COLOR_SELECT:
    return "Selection: active list row or value being edited.";
  case CONFIG_NIO_COLOR_STATUS:
    return "Status: lower information panel text and background.";
  case CONFIG_NIO_COLOR_INACTIVE:
    return "Inactive: unfocused window borders and normal inactive text.";
  case CONFIG_NIO_COLOR_INACTIVE_SELECT:
    return "Inactive selection: selected row in an unfocused pane.";
  case CONFIG_NIO_COLOR_MENUBAR:
    return "Menu: top menu bar background and normal menu text.";
  case CONFIG_NIO_COLOR_MENUHOT:
    return "Menu hotkey: highlighted shortcut letters in the menu bar.";
  case CONFIG_NIO_COLOR_TITLEBAR:
    return "Title bar: full-width top application title.";
  case CONFIG_NIO_COLOR_BUTTON:
    return "Button: normal modal button text and background.";
  case CONFIG_NIO_COLOR_BUTTON_SELECT:
    return "Button select: focused modal button text and background.";
  default:
    return "Color role.";
  }
}

static const char *dos_pref_status(void)
{
  if (!dos_pref_editing)
    return "";
  if (dos_selected_pref < 2)
    return "Editing value; Enter saves, Esc cancels.";
  return dos_pref_edit_field ? "Editing background color." : "Editing foreground color.";
}

static uint8_t dos_pref_total_prefs(void)
{
  return (uint8_t) (CONFIG_NIO_COLOR_COUNT + 2);
}

static uint8_t dos_pref_total_rows(void)
{
  return (uint8_t) (CONFIG_NIO_COLOR_COUNT + 7);
}

static uint8_t dos_pref_display_row(uint8_t pref)
{
  if (pref < 2)
    return (uint8_t) (pref + 1);
  return (uint8_t) (pref + 4);
}

static uint8_t dos_pref_from_display_row(uint8_t row)
{
  if (row == DOS_PREF_FORMAT_TOP || row == DOS_PREF_FORMAT_BOTTOM ||
      row == DOS_PREF_COLOR_TOP || row == DOS_PREF_COLOR_HEADER ||
      row + 1 == dos_pref_total_rows())
    return DOS_PREF_GROUP_NONE;
  if (row > DOS_PREF_FORMAT_TOP && row < DOS_PREF_FORMAT_BOTTOM)
    return (uint8_t) (row - 1);
  if (row > DOS_PREF_COLOR_HEADER)
    return (uint8_t) (row - 4);
  return DOS_PREF_GROUP_NONE;
}

static uint8_t dos_pref_section_top(uint8_t pref)
{
  if (pref < 2)
    return DOS_PREF_FORMAT_TOP;
  return DOS_PREF_COLOR_TOP;
}

static void dos_pref_ensure_visible(void)
{
  uint8_t row;
  uint8_t bottom;
  uint8_t section_top;
  uint8_t top;

  row = dos_pref_display_row(dos_selected_pref);
  bottom = row;
  if (dos_selected_pref == 1 || dos_selected_pref + 1 == dos_pref_total_prefs())
    bottom = (uint8_t) (row + 1);
  section_top = dos_pref_section_top(dos_selected_pref);
  top = row;
  if (row > 1)
    top = (uint8_t) (row - 2);
  if (top < section_top)
    top = section_top;
  if (row < dos_pref_scroll)
    dos_pref_scroll = top;
  while (bottom >=
         (uint8_t) (dos_pref_scroll + DOS_PREF_VISIBLE_ROWS))
    dos_pref_scroll++;
  if (row - dos_pref_scroll < 2 && dos_pref_scroll > section_top)
    dos_pref_scroll = top;
}

static void dos_pref_hline(WINDOW *win, int y, int left, int width,
                           const char *label)
{
  int n;

  wattrset(win, COLOR_PAIR(DOS_COLOR_FRAME));
  wmove(win, y, left);
  waddch(win, label && label[0] ? ACS_ULCORNER : ACS_LLCORNER);
  if (label && label[0]) {
    waddch(win, ACS_HLINE);
    waddch(win, ' ');
    wattrset(win, COLOR_PAIR(DOS_COLOR_TITLE));
    dos_curses_print_clip(win, label, 12);
    wattrset(win, COLOR_PAIR(DOS_COLOR_FRAME));
    waddch(win, ' ');
    n = 16;
  } else {
    n = 1;
  }
  while (n < width - 1) {
    waddch(win, ACS_HLINE);
    n++;
  }
  waddch(win, label && label[0] ? ACS_URCORNER : ACS_LRCORNER);
}

static void dos_draw_pref_row(WINDOW *win, int y, config_nio_state_t *state,
                              uint8_t row)
{
  uint8_t pref;

  if (row == DOS_PREF_FORMAT_TOP) {
    dos_pref_hline(win, y, 1, 48, "Formatting");
    return;
  }
  if (row == DOS_PREF_FORMAT_BOTTOM) {
    dos_pref_hline(win, y, 1, 48, "");
    return;
  }
  if (row == DOS_PREF_COLOR_TOP) {
    dos_pref_hline(win, y, 1, 48, "Colours");
    return;
  }
  if (row == DOS_PREF_COLOR_HEADER) {
    wattrset(win, COLOR_PAIR(DOS_COLOR_FRAME));
    mvwaddch(win, y, 1, ACS_VLINE);
    wattrset(win, COLOR_PAIR(DOS_COLOR_TITLE));
    mvwaddstr(win, y, DOS_PREF_FG_X, "fg");
    mvwaddstr(win, y, DOS_PREF_BG_X, "bg");
    wattrset(win, COLOR_PAIR(DOS_COLOR_FRAME));
    mvwaddch(win, y, 48, ACS_VLINE);
    return;
  }
  if (row + 1 == dos_pref_total_rows()) {
    dos_pref_hline(win, y, 1, 48, "");
    return;
  }
  pref = dos_pref_from_display_row(row);
  if (pref == 0) {
    dos_draw_pref_base(win, y, pref, "Date format");
    dos_draw_pref_value(win, y, pref,
                        state->prefs.date_format == CONFIG_NIO_PREF_DATE_YDM ?
                        "YY-DD-MM" : "YY-MM-DD");
  } else if (pref == 1) {
    dos_draw_pref_base(win, y, pref, "Size format");
    dos_draw_pref_value(win, y, pref,
                        state->prefs.size_format == CONFIG_NIO_PREF_SIZE_COMPACT ?
                        "Compact" : "Full");
  } else if (pref < dos_pref_total_prefs()) {
    dos_draw_pref_color_line(win, y, state, (uint8_t) (pref - 2));
  }
}

static void dos_draw_pref_base(WINDOW *win, int y, uint8_t pref, const char *label)
{
  int selected;

  selected = pref == dos_selected_pref && !dos_pref_editing;
  wattrset(win, COLOR_PAIR(DOS_COLOR_BODY));
  wattrset(win, COLOR_PAIR(DOS_COLOR_FRAME));
  mvwaddch(win, y, 1, ACS_VLINE);
  wattrset(win, COLOR_PAIR(DOS_COLOR_BODY));
  wmove(win, y, 2);
  dos_curses_print_clip(win, "", 46);
  wattrset(win, COLOR_PAIR(DOS_COLOR_FRAME));
  mvwaddch(win, y, 48, ACS_VLINE);
  dos_set_list_attr(win, selected, 1);
  wmove(win, y, DOS_PREF_LABEL_X);
  dos_curses_print_clip(win, label, DOS_PREF_LABEL_W);
}

static void dos_draw_pref_value(WINDOW *win, int y, uint8_t pref, const char *value)
{
  int selected;

  selected = pref == dos_selected_pref && dos_pref_editing;
  if (selected)
    dos_set_list_attr(win, 1, 1);
  else
    wattrset(win, COLOR_PAIR(DOS_COLOR_BODY));
  wmove(win, y, DOS_PREF_VALUE_X);
  dos_curses_print_clip(win, value, DOS_PREF_VALUE_W);
}

static void dos_draw_pref_color_line(WINDOW *win, int y, config_nio_state_t *state,
                                     uint8_t role)
{
  int selected_fg;
  int selected_bg;

  dos_draw_pref_base(win, y, (uint8_t) (role + 2), dos_pref_role_name(role));
  selected_fg = dos_selected_pref == (uint8_t) (role + 2) &&
                dos_pref_editing && dos_pref_edit_field == 0;
  selected_bg = dos_selected_pref == (uint8_t) (role + 2) &&
                dos_pref_editing && dos_pref_edit_field == 1;
  if (selected_fg)
    dos_set_list_attr(win, 1, 1);
  else
    wattrset(win, COLOR_PAIR(DOS_COLOR_BODY));
  wmove(win, y, DOS_PREF_FG_X);
  dos_curses_print_clip(win, dos_pref_color_name(state->prefs.color_fg[role]),
                        DOS_PREF_COLOR_W);
  if (selected_bg)
    dos_set_list_attr(win, 1, 1);
  else
    wattrset(win, COLOR_PAIR(DOS_COLOR_BODY));
  wmove(win, y, DOS_PREF_BG_X);
  dos_curses_print_clip(win, dos_pref_color_name(state->prefs.color_bg[role]),
                        DOS_PREF_COLOR_W);
}

static void dos_draw_prefs_screen(config_nio_state_t *state)
{
  uint8_t i;
  uint8_t row;
  uint8_t total;

  dos_pref_ensure_visible();
  total = dos_pref_total_rows();
  dos_clear_window(dos_main_win, DOS_COLOR_BODY);
  dos_win_title_focus(dos_main_win, " Preferences ", 1);
  if (dos_pref_scroll > 0)
    mvwaddch(dos_main_win, 1, 46, '^');
  if ((uint8_t) (dos_pref_scroll + DOS_PREF_VISIBLE_ROWS) < total)
    mvwaddch(dos_main_win, 15, 46, 'v');

  for (i = 0; i < DOS_PREF_VISIBLE_ROWS; i++) {
    row = (uint8_t) (dos_pref_scroll + i);
    if (row >= total)
      break;
    dos_draw_pref_row(dos_main_win, (int) i + DOS_PREF_FIRST_Y, state, row);
  }
  wnoutrefresh(dos_main_win);

  dos_clear_window(dos_side_win, DOS_COLOR_BODY);
  dos_win_title_focus(dos_side_win, " Edit ", 0);
  wattrset(dos_side_win, COLOR_PAIR(DOS_COLOR_BODY));
  if (dos_pref_editing) {
    mvwaddstr(dos_side_win, 2, 2, "Editing");
    mvwaddstr(dos_side_win, 4, 2, "Enter saves");
    mvwaddstr(dos_side_win, 5, 2, "Esc cancels");
    if (dos_selected_pref >= 2) {
      mvwaddstr(dos_side_win, 7, 2, "Left/Right fg/bg");
      mvwaddstr(dos_side_win, 8, 2, "Up/Down color");
    } else {
      mvwaddstr(dos_side_win, 7, 2, "Up/Down value");
    }
  } else {
    mvwaddstr(dos_side_win, 2, 2, "Arrows choose");
    mvwaddstr(dos_side_win, 3, 2, "E edits");
    mvwaddstr(dos_side_win, 5, 2, "R reset row");
    mvwaddstr(dos_side_win, 6, 2, "D defaults");
  }
  wnoutrefresh(dos_side_win);
  dos_draw_status(dos_pref_description(), dos_pref_status());
}

static void dos_list_cb(uint8_t is_dir, const char *name, uint32_t size,
                        uint32_t mtime, void *ctx)
{
  config_nio_state_t *state;
  config_nio_entry_t *entry;
  uint16_t n;

  state = (config_nio_state_t *) ctx;
  state->entry_total++;
  if (state->entry_count >= CONFIG_NIO_MAX_ENTRIES) {
    state->entries_truncated = 1;
    return;
  }
  entry = &state->entries[state->entry_count++];
  entry->is_dir = is_dir;
  entry->size = size;
  entry->mtime = mtime;
  n = (uint16_t) strlen(name);
  if (n > CONFIG_NIO_NAME_MAX)
    n = CONFIG_NIO_NAME_MAX;
  memcpy(entry->name, name, n);
  entry->name[n] = 0;
}

static int dos_refresh_entries(config_nio_state_t *state)
{
  state->entry_count = 0;
  state->entry_total = 0;
  state->entries_truncated = 0;
  if (!config_nio_compose_uri(state->hosts[dos_browser_host],
                              state->browse_path, "",
                              dos_uri_buf, sizeof(dos_uri_buf))) {
    config_nio_set_status(state, "Path is too long");
    return 0;
  }
  if (!fnsvc_list_directory(dos_uri_buf, dos_list_cb, state)) {
    sprintf(dos_status_buf, "Browse failed: error %u status %u",
            (unsigned) fnsvc_last_error(),
            (unsigned) fnsvc_last_status());
    config_nio_set_status(state, dos_status_buf);
    return 0;
  }
  if (dos_selected_entry >= state->entry_count)
    dos_selected_entry = 0;
  config_nio_set_status(state, state->entries_truncated ? "Entries loaded (more)" : "Entries loaded");
  dos_browser_cache_valid = 1;
  return 1;
}

static void dos_parent_cache_save(config_nio_state_t *state)
{
  if (!state)
    return;
  dos_parent_cache_valid = 1;
  dos_parent_cache_host = dos_browser_host;
  dos_parent_cache_count = state->entry_count;
  dos_parent_cache_total = state->entry_total;
  dos_parent_cache_truncated = state->entries_truncated;
  dos_parent_cache_selected = dos_selected_entry;
  strcpy(dos_parent_cache_path, state->browse_path);
  memcpy(dos_parent_cache_entries, state->entries,
         sizeof(dos_parent_cache_entries));
}

static int dos_parent_cache_restore(config_nio_state_t *state)
{
  if (!state || !dos_parent_cache_valid)
    return 0;
  if (dos_parent_cache_host != dos_browser_host)
    return 0;
  if (strcmp(dos_parent_cache_path, state->browse_path) != 0)
    return 0;
  state->entry_count = dos_parent_cache_count;
  state->entry_total = dos_parent_cache_total;
  state->entries_truncated = dos_parent_cache_truncated;
  memcpy(state->entries, dos_parent_cache_entries,
         sizeof(dos_parent_cache_entries));
  dos_selected_entry = dos_parent_cache_selected;
  if (dos_selected_entry >= state->entry_count)
    dos_selected_entry = 0;
  dos_browser_cache_valid = 1;
  config_nio_set_status(state, "Entries restored from cache");
  return 1;
}

static void dos_browser_invalidate(config_nio_state_t *state)
{
  dos_browser_cache_valid = 0;
  dos_parent_cache_valid = 0;
  if (state) {
    state->entry_count = 0;
    state->entry_total = 0;
    state->entries_truncated = 0;
  }
}

static void dos_anim_reset(void)
{
  dos_anim_kind = DOS_ANIM_NONE;
  dos_anim_index = 0xff;
  dos_anim_offset = 0;
  dos_anim_pause = DOS_ANIM_END_PAUSE;
  dos_anim_dir = -1;
}

static void dos_anim_tick(config_nio_state_t *state)
{
  config_nio_entry_t *entry;
  const char *text;
  uint16_t len;
  uint8_t max_offset;
  uint8_t kind;
  uint8_t index;
  uint8_t width;

  text = NULL;
  kind = DOS_ANIM_NONE;
  index = 0;
  width = 0;

  if (dos_screen == DOS_SCREEN_BROWSE && dos_browse_focus == 0 &&
      dos_selected_entry < state->entry_count) {
    entry = &state->entries[dos_selected_entry];
    text = entry->name;
    kind = DOS_ANIM_BROWSE;
    index = dos_selected_entry;
    width = 24;
  } else if (dos_screen == DOS_SCREEN_SLOTS &&
             dos_selected_slot < FNCTL_MAX_UNITS &&
             state->slots[dos_selected_slot].enabled &&
             state->slots[dos_selected_slot].uri[0]) {
    text = state->slots[dos_selected_slot].uri;
    kind = DOS_ANIM_SLOT;
    index = dos_selected_slot;
    width = 39;
  } else {
    return;
  }

  len = (uint16_t) strlen(text);
  if (len <= width)
    return;
  max_offset = (uint8_t) (len - width);
  if (dos_anim_kind != kind || dos_anim_index != index) {
    dos_anim_kind = kind;
    dos_anim_index = index;
    dos_anim_offset = max_offset;
    dos_anim_dir = -1;
    dos_anim_pause = DOS_ANIM_END_PAUSE;
    return;
  }
  if (dos_anim_pause > 0) {
    dos_anim_pause--;
    return;
  }
  if (dos_anim_dir < 0) {
    if (dos_anim_offset == 0) {
      dos_anim_dir = 1;
      dos_anim_pause = DOS_ANIM_END_PAUSE;
    } else {
      dos_anim_offset--;
    }
  } else {
    if (dos_anim_offset >= max_offset) {
      dos_anim_dir = -1;
      dos_anim_pause = DOS_ANIM_END_PAUSE;
    } else {
      dos_anim_offset++;
    }
  }
}

static void dos_switch_screen(config_nio_state_t *state, uint8_t screen)
{
  if (dos_screen == DOS_SCREEN_BROWSE && screen != DOS_SCREEN_BROWSE)
    dos_browser_invalidate(state);
  if (dos_screen == DOS_SCREEN_PREFS && screen != DOS_SCREEN_PREFS) {
    dos_pref_cancel_edit(state);
    dos_force_full_redraw();
  }
  dos_screen = screen;
}

static void dos_parent_path(char *path)
{
  uint16_t len;

  len = (uint16_t) strlen(path);
  while (len > 0 && path[len - 1] == '/')
    path[--len] = 0;
  while (len > 0 && path[len - 1] != '/')
    path[--len] = 0;
}

static int dos_enter_dir(config_nio_state_t *state, const char *name)
{
  uint16_t len;
  uint16_t nlen;

  len = (uint16_t) strlen(state->browse_path);
  nlen = (uint16_t) strlen(name);
  if ((uint16_t) (len + nlen + 2) > FNSVC_MAX_PATH) {
    config_nio_set_status(state, "Path is too long");
    return 0;
  }
  if (len > 0 && state->browse_path[len - 1] != '/')
    state->browse_path[len++] = '/';
  memcpy(&state->browse_path[len], name, nlen);
  len = (uint16_t) (len + nlen);
  state->browse_path[len++] = '/';
  state->browse_path[len] = 0;
  return 1;
}

static void dos_draw_browser(config_nio_state_t *state)
{
  uint8_t i;
  uint8_t start;
  uint8_t row;

  dos_clear_window(dos_main_win, DOS_COLOR_BODY);
  dos_win_title_focus(dos_main_win, " Browse ", dos_browse_focus == 0);
  wattrset(dos_main_win, COLOR_PAIR(DOS_COLOR_TITLE));
  wmove(dos_main_win, 1, 2);
  dos_curses_print_tail(dos_main_win, state->hosts[dos_browser_host], 22);
  waddch(dos_main_win, '/');
  dos_curses_print_tail(dos_main_win, state->browse_path, 20);
  start = 0;
  if (dos_selected_entry >= 12)
    start = (uint8_t) (dos_selected_entry - 11);
  row = 0;
  for (i = start; i < state->entry_count && row < 12; i++, row++) {
    dos_draw_browser_entry(state, i, row);
  }
  if (state->entry_count == 0) {
    wattrset(dos_main_win, COLOR_PAIR(DOS_COLOR_BODY));
    mvwaddstr(dos_main_win, 3, 2, "(empty)");
  }
  wnoutrefresh(dos_main_win);

  dos_clear_window(dos_side_win, DOS_COLOR_BODY);
  dos_win_title_focus(dos_side_win, " Slots ", dos_browse_focus == 1);
  for (i = 0; i < FNCTL_MAX_UNITS; i++) {
    config_nio_slot_t *mount;
    int selected;

    mount = &state->slots[i];
    selected = i == dos_selected_slot;
    if (selected && dos_browse_focus == 1)
      wattrset(dos_side_win, COLOR_PAIR(DOS_COLOR_SELECT));
    else if (selected)
      wattrset(dos_side_win, COLOR_PAIR(DOS_COLOR_INACTIVE_SELECT));
    else
      wattrset(dos_side_win, COLOR_PAIR(DOS_COLOR_BODY));
    mvwprintw(dos_side_win, (int) i + 2, 2, "%u ", (unsigned) i);
    if (mount->enabled && mount->uri[0])
      dos_curses_print_tail(dos_side_win, mount->uri, 18);
    else
      dos_curses_print_clip(dos_side_win, "(empty)", 18);
  }
  wnoutrefresh(dos_side_win);
  dos_draw_status("Browse: Tab switches Browse/Slots, arrows move focused pane, Enter acts",
                  dos_browse_status(state));
}

static void dos_draw_shell(void)
{
  if (dos_last_screen != (int) dos_screen) {
    erase();
    bkgd(COLOR_PAIR(DOS_COLOR_BODY));
    dos_last_screen = dos_screen;
  }
  dos_draw_titlebar();
  dos_draw_menu();
}

static void dos_force_full_redraw(void)
{
  int y;
  int x;

  dos_last_screen = -1;
  bkgd(COLOR_PAIR(DOS_COLOR_BODY));
  attrset(COLOR_PAIR(DOS_COLOR_BODY));
  clear();
  for (y = 0; y < 25; y++) {
    move(y, 0);
    for (x = 0; x < 80; x++)
      addch(' ');
  }
  clearok(stdscr, TRUE);
  refresh();
  if (dos_main_win) {
    dos_clear_window(dos_main_win, DOS_COLOR_BODY);
    clearok(dos_main_win, TRUE);
    touchwin(dos_main_win);
  }
  if (dos_side_win) {
    dos_clear_window(dos_side_win, DOS_COLOR_BODY);
    clearok(dos_side_win, TRUE);
    touchwin(dos_side_win);
  }
  if (dos_status_win) {
    dos_clear_window(dos_status_win, DOS_COLOR_STATUS);
    clearok(dos_status_win, TRUE);
    touchwin(dos_status_win);
  }
  touchwin(stdscr);
}

static void dos_mark_full_redraw(void)
{
  dos_last_screen = -1;
  clearok(stdscr, TRUE);
  if (dos_main_win) {
    clearok(dos_main_win, TRUE);
    touchwin(dos_main_win);
  }
  if (dos_side_win) {
    clearok(dos_side_win, TRUE);
    touchwin(dos_side_win);
  }
  if (dos_status_win) {
    clearok(dos_status_win, TRUE);
    touchwin(dos_status_win);
  }
  touchwin(stdscr);
}

static void dos_seed_default_prefs(config_nio_prefs_t *prefs)
{
  prefs->date_format = CONFIG_NIO_PREF_DATE_YMD;
  prefs->size_format = CONFIG_NIO_PREF_SIZE_FULL;
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
}

static void dos_redraw_app(config_nio_state_t *state)
{
  dos_draw_shell();

  if (dos_screen == DOS_SCREEN_HOSTS)
    dos_draw_hosts(state);
  else if (dos_screen == DOS_SCREEN_BROWSE)
    dos_draw_browser(state);
  else if (dos_screen == DOS_SCREEN_SLOTS)
    dos_draw_slots_screen(state);
  else if (dos_screen == DOS_SCREEN_PREFS)
    dos_draw_prefs_screen(state);
  else
    dos_draw_slots_screen(state);
  doupdate();
}

static void dos_open_browser(config_nio_state_t *state, uint8_t host)
{
  if (host >= state->host_count) {
    config_nio_set_status(state, "No host selected");
    return;
  }
  dos_browser_host = host;
  dos_selected_host = host;
  dos_selected_entry = 0;
  dos_browse_focus = 0;
  state->browse_path[0] = 0;
  dos_browser_cache_valid = 0;
  config_nio_set_status(state, "");
  if (!dos_refresh_entries(state)) {
    dos_message_ok(" Error ", "Error connecting to host");
    return;
  }
  dos_switch_screen(state, DOS_SCREEN_BROWSE);
}

static void dos_add_host(config_nio_state_t *state)
{
  if (state->host_count >= CONFIG_NIO_MAX_HOSTS) {
    config_nio_set_status(state, "Host list is full");
    return;
  }
  dos_uri_edit[0] = 0;
  if (dos_curses_prompt(" Add host ", "Host", dos_uri_edit, sizeof(dos_uri_edit)) &&
      dos_uri_edit[0]) {
    strcpy(state->hosts[state->host_count], dos_uri_edit);
    dos_selected_host = state->host_count;
    state->host_count++;
    (void) config_nio_save_hosts(state);
    config_nio_set_status(state, "Host added");
  }
}

static void dos_edit_host(config_nio_state_t *state)
{
  if (state->host_count == 0 || dos_selected_host >= state->host_count) {
    config_nio_set_status(state, "No host selected");
    return;
  }
  strcpy(dos_uri_edit, state->hosts[dos_selected_host]);
  if (dos_curses_prompt(" Edit host ", "Host", dos_uri_edit, sizeof(dos_uri_edit)) &&
      dos_uri_edit[0]) {
    strcpy(state->hosts[dos_selected_host], dos_uri_edit);
    (void) config_nio_save_hosts(state);
    config_nio_set_status(state, "Host updated");
  }
}

static void dos_delete_host(config_nio_state_t *state)
{
  uint8_t i;

  if (state->host_count == 0 || dos_selected_host >= state->host_count) {
    config_nio_set_status(state, "No host selected");
    return;
  }
  for (i = dos_selected_host; i + 1 < state->host_count; i++)
    strcpy(state->hosts[i], state->hosts[i + 1]);
  state->host_count--;
  if (dos_selected_host >= state->host_count && dos_selected_host > 0)
    dos_selected_host--;
  (void) config_nio_save_hosts(state);
  config_nio_set_status(state, "Host deleted");
}

static void dos_move_host(config_nio_state_t *state, int delta)
{
  uint8_t other;

  if (state->host_count == 0)
    return;
  if (delta < 0 && dos_selected_host == 0)
    return;
  if (delta > 0 && dos_selected_host + 1 >= state->host_count)
    return;
  other = (uint8_t) (dos_selected_host + delta);
  strcpy(dos_uri_buf, state->hosts[dos_selected_host]);
  strcpy(state->hosts[dos_selected_host], state->hosts[other]);
  strcpy(state->hosts[other], dos_uri_buf);
  dos_selected_host = other;
  (void) config_nio_save_hosts(state);
  config_nio_set_status(state, "Host moved");
}

static void dos_assign_selected_entry(config_nio_state_t *state)
{
  if (state->entry_count == 0 || dos_selected_entry >= state->entry_count)
    return;
  if (state->entries[dos_selected_entry].is_dir & CONFIG_NIO_ENTRY_FLAG_NAME_TRUNCATED) {
    config_nio_set_status(state, "Name too long for this client");
    return;
  }
  if (state->entries[dos_selected_entry].is_dir & CONFIG_NIO_ENTRY_FLAG_DIR) {
    config_nio_set_status(state, "Pick a file, not a directory");
    return;
  }
  if (!config_nio_compose_uri(state->hosts[dos_browser_host], state->browse_path,
                              state->entries[dos_selected_entry].name,
                              dos_uri_buf, sizeof(dos_uri_buf))) {
    config_nio_set_status(state, "URI is too long");
    return;
  }
  if (!fnsvc_set_mount(dos_selected_slot, dos_uri_buf, "rw", 1)) {
    config_nio_set_status(state, "Unable to save slot");
    return;
  }
  (void) config_nio_refresh_slots(state);
  config_nio_set_status(state, "Assigned file to selected slot");
}

static void dos_browser_enter(config_nio_state_t *state)
{
  if (state->entry_count == 0 || dos_selected_entry >= state->entry_count)
    return;
  if (dos_browse_focus == 1) {
    dos_assign_selected_entry(state);
    return;
  }
  if (state->entries[dos_selected_entry].is_dir & CONFIG_NIO_ENTRY_FLAG_NAME_TRUNCATED) {
    config_nio_set_status(state, "Name too long for this client");
    return;
  }
  if (state->entries[dos_selected_entry].is_dir & CONFIG_NIO_ENTRY_FLAG_DIR) {
    dos_parent_cache_save(state);
    if (dos_enter_dir(state, state->entries[dos_selected_entry].name)) {
      dos_selected_entry = 0;
      dos_anim_reset();
      dos_browser_cache_valid = 0;
      (void) dos_refresh_entries(state);
    }
  } else {
    dos_assign_selected_entry(state);
  }
}

static void dos_handle_up(config_nio_state_t *state)
{
  (void) state;
  if (dos_screen == DOS_SCREEN_HOSTS && dos_selected_host > 0)
    dos_selected_host--;
  else if (dos_screen == DOS_SCREEN_BROWSE) {
    if (dos_browse_focus == 0 && dos_selected_entry > 0)
      dos_selected_entry--;
    else if (dos_browse_focus == 1 && dos_selected_slot > 0)
      dos_selected_slot--;
  }
  else if (dos_screen == DOS_SCREEN_SLOTS && dos_focus == 0 &&
           dos_selected_slot > 0)
    dos_selected_slot--;
  else if (dos_screen == DOS_SCREEN_SLOTS && dos_focus == 1 &&
           dos_selected_unit > 0)
    dos_selected_unit--;
  else if (dos_screen == DOS_SCREEN_PREFS && dos_selected_pref > 0)
    dos_selected_pref--;
  if (dos_screen == DOS_SCREEN_PREFS)
    dos_pref_ensure_visible();
}

static void dos_handle_down(config_nio_state_t *state)
{
  if (dos_screen == DOS_SCREEN_HOSTS && dos_selected_host + 1 < state->host_count)
    dos_selected_host++;
  else if (dos_screen == DOS_SCREEN_BROWSE) {
    if (dos_browse_focus == 0 && dos_selected_entry + 1 < state->entry_count)
      dos_selected_entry++;
    else if (dos_browse_focus == 1 && dos_selected_slot + 1 < FNCTL_MAX_UNITS)
      dos_selected_slot++;
  }
  else if (dos_screen == DOS_SCREEN_SLOTS && dos_focus == 0 &&
           dos_selected_slot + 1 < FNCTL_MAX_UNITS)
    dos_selected_slot++;
  else if (dos_screen == DOS_SCREEN_SLOTS && dos_focus == 1 &&
           dos_selected_unit + 1 < FNCTL_MAX_UNITS)
    dos_selected_unit++;
  else if (dos_screen == DOS_SCREEN_PREFS &&
           dos_selected_pref + 1 < dos_pref_total_prefs())
    dos_selected_pref++;
  if (dos_screen == DOS_SCREEN_PREFS)
    dos_pref_ensure_visible();
}

static void dos_save_prefs(config_nio_state_t *state)
{
  dos_init_colors(&state->prefs);
  dos_force_full_redraw();
  (void) config_nio_save_prefs(state);
  config_nio_set_status(state, "Preferences saved");
}

static void dos_pref_preview(config_nio_state_t *state)
{
  dos_init_colors(&state->prefs);
  dos_force_full_redraw();
  config_nio_set_status(state, "Previewing preference change");
}

static void dos_pref_begin_edit(config_nio_state_t *state)
{
  uint8_t role;

  if (dos_pref_editing)
    return;
  dos_pref_editing = 1;
  dos_pref_edit_field = 0;
  dos_pref_saved_date = state->prefs.date_format;
  dos_pref_saved_size = state->prefs.size_format;
  dos_pref_saved_fg = 0;
  dos_pref_saved_bg = 0;
  if (dos_selected_pref >= 2) {
    role = (uint8_t) (dos_selected_pref - 2);
    if (role < CONFIG_NIO_COLOR_COUNT) {
      dos_pref_saved_fg = state->prefs.color_fg[role];
      dos_pref_saved_bg = state->prefs.color_bg[role];
    }
  }
  config_nio_set_status(state, "Editing preference");
}

static void dos_pref_commit_edit(config_nio_state_t *state)
{
  if (!dos_pref_editing)
    return;
  dos_pref_editing = 0;
  dos_save_prefs(state);
}

static void dos_pref_cancel_edit(config_nio_state_t *state)
{
  uint8_t role;

  if (!dos_pref_editing)
    return;
  state->prefs.date_format = dos_pref_saved_date;
  state->prefs.size_format = dos_pref_saved_size;
  if (dos_selected_pref >= 2) {
    role = (uint8_t) (dos_selected_pref - 2);
    if (role < CONFIG_NIO_COLOR_COUNT) {
      state->prefs.color_fg[role] = dos_pref_saved_fg;
      state->prefs.color_bg[role] = dos_pref_saved_bg;
    }
  }
  dos_pref_editing = 0;
  dos_init_colors(&state->prefs);
  dos_force_full_redraw();
  config_nio_set_status(state, "Preference edit cancelled");
}

static void dos_reset_selected_pref(config_nio_state_t *state)
{
  config_nio_prefs_t defaults;
  uint8_t role;

  dos_seed_default_prefs(&defaults);
  if (dos_selected_pref == 0) {
    state->prefs.date_format = defaults.date_format;
  } else if (dos_selected_pref == 1) {
    state->prefs.size_format = defaults.size_format;
  } else {
    role = (uint8_t) (dos_selected_pref - 2);
    if (role >= CONFIG_NIO_COLOR_COUNT)
      return;
    state->prefs.color_fg[role] = defaults.color_fg[role];
    state->prefs.color_bg[role] = defaults.color_bg[role];
  }
  dos_save_prefs(state);
  config_nio_set_status(state, "Preference reset");
}

static void dos_reset_all_prefs(config_nio_state_t *state)
{
  dos_seed_default_prefs(&state->prefs);
  dos_save_prefs(state);
  config_nio_set_status(state, "Default preferences restored");
}

static void dos_pref_change_value(config_nio_state_t *state, int delta)
{
  uint8_t role;
  uint8_t *value;

  if (!dos_pref_editing)
    return;
  if (dos_selected_pref == 0) {
    state->prefs.date_format = (uint8_t) !state->prefs.date_format;
    dos_pref_preview(state);
    return;
  }
  if (dos_selected_pref == 1) {
    state->prefs.size_format = (uint8_t) !state->prefs.size_format;
    dos_pref_preview(state);
    return;
  }
  role = (uint8_t) (dos_selected_pref - 2);
  if (role >= CONFIG_NIO_COLOR_COUNT)
    return;
  value = dos_pref_edit_field ? &state->prefs.color_bg[role] :
                                &state->prefs.color_fg[role];
  if (delta < 0)
    *value = (uint8_t) ((*value + 7) & 7);
  else
    *value = (uint8_t) ((*value + 1) & 7);
  dos_pref_preview(state);
}

static int dos_handle_pref_edit_key(config_nio_state_t *state, int key)
{
  if (!dos_pref_editing)
    return 0;
  if (dos_key_is_escape(key)) {
    dos_pref_cancel_edit(state);
    return 1;
  }
  if (key == DOS_KEY_ENTER || key == '\n' || key == '\r') {
    dos_pref_commit_edit(state);
    return 1;
  }
  if (key == KEY_LEFT && dos_selected_pref >= 2) {
    dos_pref_edit_field = 0;
    return 1;
  }
  if (key == KEY_RIGHT && dos_selected_pref >= 2) {
    dos_pref_edit_field = 1;
    return 1;
  }
  if (key == KEY_UP) {
    dos_pref_change_value(state, -1);
    return 1;
  }
  if (key == KEY_DOWN) {
    dos_pref_change_value(state, 1);
    return 1;
  }
  return 1;
}

static int dos_handle_key(config_nio_state_t *state, int key)
{
  if (dos_screen == DOS_SCREEN_PREFS && dos_pref_editing)
    return dos_handle_pref_edit_key(state, key);

  if (dos_key_is_quit(key)) {
    if (dos_confirm_quit())
      return 0;
    config_nio_set_status(state, "Quit cancelled");
    return 1;
  }
  if (key == 'h' || key == 'H') {
    config_nio_set_status(state, "");
    dos_switch_screen(state, DOS_SCREEN_HOSTS);
    return 1;
  }
  if (key == 's' || key == 'S') {
    dos_switch_screen(state, DOS_SCREEN_SLOTS);
    config_nio_set_status(state, "");
    return 1;
  }
  if (key == 'p' || key == 'P') {
    dos_pref_scroll = 0;
    dos_switch_screen(state, DOS_SCREEN_PREFS);
    config_nio_set_status(state, "Preferences: edit saved display settings");
    return 1;
  }
  if (key == 'x' || key == 'X') {
    (void) config_nio_mount_mappings(state);
    return 0;
  }
  if (key == KEY_UP) {
    dos_handle_up(state);
    return 1;
  }
  if (key == KEY_DOWN) {
    dos_handle_down(state);
    return 1;
  }
  if ((key == DOS_KEY_TAB || key == KEY_LEFT || key == KEY_RIGHT) &&
      (dos_screen == DOS_SCREEN_SLOTS || dos_screen == DOS_SCREEN_BROWSE)) {
    if (dos_screen == DOS_SCREEN_SLOTS) {
      dos_focus = (uint8_t) !dos_focus;
      config_nio_set_status(state, dos_focus ? "Drives pane active" : "Slots pane active");
    } else {
      dos_browse_focus = (uint8_t) !dos_browse_focus;
      config_nio_set_status(state, dos_browse_focus ? "Slots pane active" : "Browse pane active");
    }
    return 1;
  }

  if (dos_screen == DOS_SCREEN_HOSTS) {
    if (key == DOS_KEY_ENTER || key == '\n' || key == '\r') {
      dos_open_browser(state, dos_selected_host);
    } else if (key == 'a' || key == 'A') {
      dos_add_host(state);
    } else if (key == 'e' || key == 'E') {
      dos_edit_host(state);
    } else if (key == 'd' || key == 'D') {
      dos_delete_host(state);
    } else if (key == '+') {
      dos_move_host(state, 1);
    } else if (key == '-') {
      dos_move_host(state, -1);
    }
  } else if (dos_screen == DOS_SCREEN_BROWSE) {
    if (key == DOS_KEY_ENTER || key == '\n' || key == '\r' ||
        key == 'e' || key == 'E') {
      dos_browser_enter(state);
    } else if (key == 'u' || key == 'U') {
      dos_parent_path(state->browse_path);
      dos_anim_reset();
      if (!dos_parent_cache_restore(state)) {
        dos_selected_entry = 0;
        dos_browser_cache_valid = 0;
        (void) dos_refresh_entries(state);
      }
    } else if (key == 'r' || key == 'R') {
      dos_parent_cache_valid = 0;
      dos_anim_reset();
      (void) dos_refresh_entries(state);
    } else if (key == 'a' || key == 'A') {
      dos_assign_selected_entry(state);
    }
  } else if (dos_screen == DOS_SCREEN_SLOTS) {
    if (key == DOS_KEY_ENTER || key == '\n' || key == '\r') {
      dos_map_selected(state);
    } else if (dos_focus == 1 && key >= '0' && key <= '7' &&
               (uint8_t) (key - '0') < FNCTL_MAX_UNITS) {
      dos_selected_slot = (uint8_t) (key - '0');
      dos_map_selected(state);
    } else if (dos_focus == 1 && (key == 'r' || key == 'R')) {
      dos_toggle_mapping_mode(state);
    } else if (key == 'c' || key == 'C') {
      if (dos_focus == 1)
        dos_clear_mapping(state);
      else
        dos_clear_slot(state);
    } else if (dos_focus == 0 && (key == 'e' || key == 'E')) {
      dos_edit_slot(state);
    } else if (dos_focus == 0 && (key == 'r' || key == 'R')) {
      (void) config_nio_refresh_slots(state);
      config_nio_set_status(state, "Slots refreshed");
    }
  } else if (dos_screen == DOS_SCREEN_PREFS) {
    if (key == 'e' || key == 'E')
      dos_pref_begin_edit(state);
    else if (key == 'r' || key == 'R')
      dos_reset_selected_pref(state);
    else if (key == 'd' || key == 'D')
      dos_reset_all_prefs(state);
  }
  return 1;
}

static void dos_map_selected(config_nio_state_t *state)
{
  state->mappings[dos_selected_unit].valid = 1;
  state->mappings[dos_selected_unit].slot = dos_selected_slot;
  if (!state->mappings[dos_selected_unit].readonly)
    state->mappings[dos_selected_unit].readonly = 0;
  (void) config_nio_save_mappings(state);
  config_nio_set_status(state, "Assigned selected slot to selected drive");
}

static void dos_toggle_mapping_mode(config_nio_state_t *state)
{
  config_nio_mapping_t *mapping;

  mapping = &state->mappings[dos_selected_unit];
  if (!mapping->valid) {
    config_nio_set_status(state, "Select an assigned drive first");
    return;
  }
  mapping->readonly = (uint8_t) !mapping->readonly;
  (void) config_nio_save_mappings(state);
  config_nio_set_status(state, mapping->readonly ? "Drive is read-only" : "Drive is read/write");
}

static void dos_clear_mapping(config_nio_state_t *state)
{
  memset(&state->mappings[dos_selected_unit], 0, sizeof(state->mappings[dos_selected_unit]));
  (void) config_nio_save_mappings(state);
  config_nio_set_status(state, "Drive assignment cleared");
}

static void dos_clear_slot(config_nio_state_t *state)
{
  if (fnsvc_set_mount(dos_selected_slot, "", "r", 0)) {
    (void) config_nio_refresh_slots(state);
    config_nio_set_status(state, "Slot cleared");
  } else {
    config_nio_set_status(state, "Unable to clear slot");
  }
}

static void dos_edit_slot(config_nio_state_t *state)
{
  strcpy(dos_uri_edit, state->slots[dos_selected_slot].uri);

  if (!dos_curses_prompt(" Edit slot ", "URI", dos_uri_edit, sizeof(dos_uri_edit)) ||
      !dos_uri_edit[0])
    return;

  if (fnsvc_set_mount(dos_selected_slot, dos_uri_edit, "rw", 1)) {
    (void) config_nio_refresh_slots(state);
    config_nio_set_status(state, "Slot saved");
  } else {
    config_nio_set_status(state, "Unable to save slot");
  }
}

void config_nio_ui_clear(void)
{
  uint8_t i;

  for (i = 0; i < 25; i++)
    fputs("\n", stdout);
}

void config_nio_ui_header(const char *title, const char *hint)
{
  fputs("+--------------------------------------------------------------------------+\n", stdout);
  fputs("| ", stdout);
  dos_print_clip(title ? title : "", 72);
  fputs(" |\n", stdout);
  fputs("+--------------------------------------------------------------------------+\n", stdout);
  if (hint && *hint) {
    fputs(hint, stdout);
    fputs("\n\n", stdout);
  }
}

void config_nio_ui_status(const char *status)
{
  fputs("\n[", stdout);
  fputs(status ? status : "", stdout);
  fputs("]\n", stdout);
}

void config_nio_ui_pause(void)
{
  (void) getch();
}

int config_nio_ui_get_key(void)
{
  return getch();
}

int config_nio_ui_prompt(const char *label, char *buf, uint16_t cap)
{
  char *p;

  if (!buf || cap == 0)
    return 0;
  fputs(label ? label : "?", stdout);
  fputs(": ", stdout);
  fflush(stdout);
  if (!fgets(buf, cap, stdin)) {
    buf[0] = 0;
    return 0;
  }
  p = strchr(buf, '\n');
  if (p)
    *p = 0;
  p = strchr(buf, '\r');
  if (p)
    *p = 0;
  return 1;
}

void config_nio_ui_putc(char c)
{
  putchar(c);
}

void config_nio_ui_print(const char *s)
{
  fputs(s ? s : "", stdout);
}

void config_nio_ui_println(const char *s)
{
  config_nio_ui_print(s);
  putchar('\n');
}

void config_nio_ui_print_uint(unsigned value)
{
  printf("%u", value);
}

void config_nio_ui_print_ulong(unsigned long value)
{
  printf("%lu", value);
}

void config_nio_ui_print_padded(const char *s, uint8_t width)
{
  uint8_t n;

  n = 0;
  while (s && *s && n < width) {
    putchar(*s++);
    n++;
  }
  while (n < width) {
    putchar(' ');
    n++;
  }
}

const char *config_nio_ui_platform_name(void)
{
  return "MS-DOS";
}

uint8_t config_nio_ui_screen_width(void)
{
  return 80;
}

uint8_t config_nio_ui_screen_height(void)
{
  return 25;
}

void config_nio_ui_drive_label(uint8_t unit, char *buf, uint8_t cap)
{
  int drive;

  if (!buf || cap == 0)
    return;
  drive = fnctl_find_drive_for_unit(unit);
  if (drive)
    sprintf(buf, "%c:", 'A' + drive - 1);
  else
    sprintf(buf, "unit%u", (unsigned) unit);
}

int config_nio_ui_show_mappings(config_nio_state_t *state)
{
  (void) state;
  return 0;
}

int config_nio_ui_run(config_nio_state_t *state)
{
  int key;
  int running;

  if (!state)
    return 1;

  if (dos_selected_host >= state->host_count)
    dos_selected_host = 0;
  if (dos_selected_slot >= FNCTL_MAX_UNITS)
    dos_selected_slot = 0;
  if (dos_selected_unit >= FNCTL_MAX_UNITS)
    dos_selected_unit = 0;

  (void) config_nio_refresh_slots(state);
  dos_screen = DOS_SCREEN_SLOTS;
  dos_focus = 0;
  dos_browse_focus = 0;
  dos_browser_cache_valid = 0;
  dos_parent_cache_valid = 0;
  dos_selected_pref = 0;
  dos_pref_scroll = 0;
  dos_pref_editing = 0;
  dos_pref_edit_field = 0;
  dos_anim_reset();

  dos_curses_start(state);
  dos_app_create_windows();
  if (!dos_main_win || !dos_side_win || !dos_status_win) {
    dos_curses_stop();
    config_nio_set_status(state, "Unable to create curses windows");
    return 1;
  }

  running = 1;
  while (running) {
    dos_redraw_app(state);
    key = wgetch(stdscr);
    if (key == ERR) {
      dos_anim_tick(state);
    } else {
      dos_anim_reset();
      running = dos_handle_key(state, key);
    }
  }

  dos_curses_stop();
  return 1;
}
