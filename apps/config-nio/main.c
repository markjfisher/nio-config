#include "config_nio.h"
#include "fujinet-nio.h"

#ifdef CONFIG_NIO_BBC_LITE
#include <conio.h>

static void fatal_message(const char *message)
{
  cputs(message);
  cputc('\r');
  cputc('\n');
  (void) cgetc();
}
#else
static void fatal_message(const char *message)
{
  config_nio_ui_println(message);
  config_nio_ui_pause();
}
#endif

static config_nio_state_t state;

int main(void)
{
  uint8_t result;

  result = fn_init();
  if (result != FN_OK) {
    fatal_message("FujiNet init failed");
    return 2;
  }

  if (!fn_is_ready()) {
    fatal_message("FujiNet is not ready");
    return 2;
  }

  if (!config_nio_load(&state)) {
    fatal_message("Unable to load config-nio state");
    return 2;
  }

  config_nio_run(&state);
  return 0;
}
