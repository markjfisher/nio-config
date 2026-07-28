#if defined(__BBC__)
#include <bbc.h>
#include <conio.h>

static void put_dec(unsigned value)
{
  char buf[6];
  unsigned i;

  i = 0;
  do {
    buf[i++] = (char) ('0' + (value % 10U));
    value = (unsigned) (value / 10U);
  } while (value && i < sizeof(buf));

  while (i)
    cputc(buf[--i]);
}

static void put_hex_digit(unsigned value)
{
  value &= 0x0f;
  cputc((char) (value < 10 ? '0' + value : 'A' + value - 10));
}

static void put_hex(unsigned value)
{
  put_hex_digit(value >> 12);
  put_hex_digit(value >> 8);
  put_hex_digit(value >> 4);
  put_hex_digit(value);
}

int main(void)
{
  int key;

  clrscr();
  cputs("KEYCODE\r\n");
  cputs("Press keys. Q quits.\r\n\r\n");
  for (;;) {
    key = cgetc();
    cputs("dec ");
    put_dec((unsigned) key);
    cputs(" hex ");
    put_hex((unsigned) key);
    cputs("\r\n");
    if (key == 'q' || key == 'Q')
      break;
  }
  return 0;
}
#else
#include <stdio.h>

int main(void)
{
  puts("keycode is only useful on BBC/Master targets.");
  return 0;
}
#endif
