#include "config_nio.h"

#include <stdint.h>
#include <string.h>

#define CONFIG_NIO_XRAM_BANK 7
#define CONFIG_NIO_XRAM_BASE ((uint8_t *) 0x8000)

void __fastcall__ config_nio_xram_begin(uint8_t bank);
void config_nio_xram_end(void);

void config_nio_xram_read(uint16_t offset, void *dst, uint16_t len)
{
  if (!dst || len == 0)
    return;
  config_nio_xram_begin(CONFIG_NIO_XRAM_BANK);
  memcpy(dst, CONFIG_NIO_XRAM_BASE + offset, len);
  config_nio_xram_end();
}

void config_nio_xram_write(uint16_t offset, const void *src, uint16_t len)
{
  if (!src || len == 0)
    return;
  config_nio_xram_begin(CONFIG_NIO_XRAM_BANK);
  memcpy(CONFIG_NIO_XRAM_BASE + offset, src, len);
  config_nio_xram_end();
}
