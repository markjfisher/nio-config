#include "config_nio.h"

#define BBC_URI_WORK_MAX (CONFIG_NIO_URI_MAX + 1)
#define BBC_BROWSE_PAGE_STACK 6

char uri_buf[BBC_URI_WORK_MAX];
const uint8_t runtime_offsets[] = { 0, 20, 40, 60 };

uint8_t hosts_start;
uint8_t browse_page_depth;

/* Shared by all BBC assembly UI handlers. The run loop sets this once for
 * the lifetime of the application; ui.s provides the common AX getter. */
uint16_t saved_state;

uint8_t current_screen;
uint8_t selected_host;
uint8_t selected_entry;
uint8_t selected_drive;
uint8_t selected_slot;
uint8_t assign_slot_start;
uint8_t slots_focus;
uint8_t browse_host;
uint16_t browse_start;
uint16_t browse_next;
uint16_t browse_page_stack[BBC_BROWSE_PAGE_STACK];
uint8_t browse_more;
