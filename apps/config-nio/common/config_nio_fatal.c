#include "config_nio.h"

void config_nio_fatal_message(const char *message)
{
  config_nio_ui_println(message);
  config_nio_ui_pause();
}
