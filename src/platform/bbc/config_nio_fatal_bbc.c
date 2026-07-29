#include "config_nio.h"

#include <conio.h>

void config_nio_fatal_message(const char *message)
{
  cputs(message);
  cputc('\r');
  cputc('\n');
  (void) cgetc();
}
