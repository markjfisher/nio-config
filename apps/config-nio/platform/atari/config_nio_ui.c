#include "config_nio.h"

#include <conio.h>
#include <string.h>

static char num_buf[11];

static void nl(void)
{
  cputc('\n');
}

void config_nio_ui_clear(void)
{
  clrscr();
}

void config_nio_ui_header(const char *title, const char *hint)
{
  cputs("+--------------------------------------+");
  nl();
  cputs("| ");
  config_nio_ui_print_padded(title ? title : "", 36);
  cputs(" |");
  nl();
  cputs("+--------------------------------------+");
  nl();
  if (hint && *hint) {
    cputs(hint);
    nl();
    nl();
  }
}

void config_nio_ui_status(const char *status)
{
  nl();
  cputc('[');
  cputs(status ? status : "");
  cputc(']');
  nl();
}

void config_nio_ui_pause(void)
{
  cgetc();
}

int config_nio_ui_get_key(void)
{
  return cgetc();
}

int config_nio_ui_prompt(const char *label, char *buf, uint16_t cap)
{
  if (!buf || cap == 0)
    return 0;
  cputs(label ? label : "?");
  cputs(": ");
  if (!cgets(buf, cap)) {
    buf[0] = 0;
    return 0;
  }
  return 1;
}

void config_nio_ui_putc(char c)
{
  cputc(c);
}

void config_nio_ui_print(const char *s)
{
  cputs(s ? s : "");
}

void config_nio_ui_println(const char *s)
{
  config_nio_ui_print(s);
  nl();
}

void config_nio_ui_print_uint(unsigned value)
{
  config_nio_ui_print_ulong((unsigned long) value);
}

void config_nio_ui_print_ulong(unsigned long value)
{
  uint8_t i;

  i = 0;
  do {
    num_buf[i++] = (char) ('0' + (value % 10UL));
    value /= 10UL;
  } while (value && i < sizeof(num_buf));

  while (i)
    cputc(num_buf[--i]);
}

void config_nio_ui_print_padded(const char *s, uint8_t width)
{
  uint8_t n;

  n = 0;
  while (s && *s && n < width) {
    cputc(*s++);
    n++;
  }
  while (n < width) {
    cputc(' ');
    n++;
  }
}

const char *config_nio_ui_platform_name(void)
{
  return "Atari";
}

uint8_t config_nio_ui_screen_width(void)
{
  return 40;
}

uint8_t config_nio_ui_screen_height(void)
{
  return 24;
}

void config_nio_ui_drive_label(uint8_t unit, char *buf, uint8_t cap)
{
  if (!buf || cap == 0)
    return;
  if (cap < 4) {
    buf[0] = 0;
    return;
  }
  buf[0] = 'D';
  buf[1] = (char) ('1' + unit);
  buf[2] = ':';
  buf[3] = 0;
}

int config_nio_ui_show_mappings(config_nio_state_t *state)
{
  (void) state;
  return 0;
}

int config_nio_ui_run(config_nio_state_t *state)
{
  (void) state;
  return 0;
}
