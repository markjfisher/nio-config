#include "config_nio.h"

#include <stdio.h>
#include <string.h>

void config_nio_ui_clear(void)
{
  fputs("\033[2J\033[H", stdout);
  fflush(stdout);
}

void config_nio_ui_header(const char *title, const char *hint)
{
  puts("+------------------------------------------------------------------------------+");
  printf("| %-76s |\n", title ? title : "");
  puts("+------------------------------------------------------------------------------+");
  if (hint && *hint)
    printf("%s\n\n", hint);
}

void config_nio_ui_status(const char *status)
{
  printf("\n[%s]\n", status ? status : "");
}

void config_nio_ui_pause(void)
{
  (void) getchar();
}

int config_nio_ui_get_key(void)
{
  int c;

  do {
    c = getchar();
  } while (c == '\n' || c == '\r');
  return c;
}

int config_nio_ui_prompt(const char *label, char *buf, uint16_t cap)
{
  char *p;

  if (!buf || cap == 0)
    return 0;
  printf("%s: ", label ? label : "?");
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
  return "Linux";
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
  if (!buf || cap == 0)
    return;
  sprintf(buf, "unit%u", (unsigned) unit);
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
