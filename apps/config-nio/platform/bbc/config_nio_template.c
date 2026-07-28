#include <stdint.h>

extern const uint8_t config_nio_tpl_hosts[];
extern const uint8_t config_nio_tpl_browse[];
extern const uint8_t config_nio_tpl_slots[];

void __fastcall__ config_nio_bbc_decompress_template(const uint8_t *src);

void config_nio_bbc_load_template(const char *asset_name)
{
  const uint8_t *src;

  if (asset_name[2] == 'H')
    src = config_nio_tpl_hosts;
  else if (asset_name[2] == 'B')
    src = config_nio_tpl_browse;
  else
    src = config_nio_tpl_slots;

  config_nio_bbc_decompress_template(src);
}
