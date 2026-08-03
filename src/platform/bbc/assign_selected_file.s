; void assign_selected_file(config_nio_state_t *state)
;
; The selected entry is copied into the app-store transfer buffer so the
; shared store buffer remains available for the host string.

        .macpack longbranch

        .export _assign_selected_file

        .import _config_nio_bbc_entry_get
        .import _config_nio_bbc_host_get
        .import _config_nio_compose_uri
        .import _config_nio_write_slot
        .import _config_nio_refresh_slots
        .import _prompt_assign_slot
        .import _config_nio_appstore_buf
        .import _config_nio_store_buf
        .import _uri_buf
        .import load_state, restore_saved_state_ptr
        .import _selected_entry
        .import _browse_host
        .import pusha, pushax
        .importzp ptr1

        .include "config_nio_host_table.inc"

STATE_ENTRY_COUNT = 5
STATE_BROWSE_PATH = 9

ENTRY_FLAGS = 0
ENTRY_NAME  = 1
ENTRY_FLAG_DIR            = $01
ENTRY_FLAG_NAME_TRUNCATED = $80

BBC_EDIT_BUF_SIZE = CONFIG_NIO_BBC_HOST_SIZE
BBC_URI_WORK_MAX  = 129

        .code

_assign_selected_file:
        jsr     restore_saved_state_ptr
        ldy     #STATE_ENTRY_COUNT
        lda     (ptr1),y
        jeq     assign_done

        lda     _selected_entry
        jsr     pusha
        lda     #<_config_nio_appstore_buf
        ldx     #>_config_nio_appstore_buf
        jsr     _config_nio_bbc_entry_get
        cmp     #0
        jeq     assign_done
        lda     _config_nio_appstore_buf+ENTRY_FLAGS
        and     #(ENTRY_FLAG_DIR | ENTRY_FLAG_NAME_TRUNCATED)
        jne     assign_done

        lda     _browse_host
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     pushax
        lda     #BBC_EDIT_BUF_SIZE
        ldx     #0
        jsr     _config_nio_bbc_host_get
        cmp     #0
        jeq     assign_done

        ; config_nio_compose_uri(host, path, leaf, out, cap)
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     pushax
        jsr     load_browse_path
        jsr     pushax
        lda     #<(_config_nio_appstore_buf+ENTRY_NAME)
        ldx     #>(_config_nio_appstore_buf+ENTRY_NAME)
        jsr     pushax
        lda     #<_uri_buf
        ldx     #>_uri_buf
        jsr     pushax
        lda     #BBC_URI_WORK_MAX
        ldx     #0
        jsr     _config_nio_compose_uri
        cmp     #0
        jeq     assign_done

        ; prompt_assign_slot(state, &chosen_slot)
        jsr     load_state
        jsr     pushax
        lda     #<chosen_slot
        ldx     #>chosen_slot
        jsr     _prompt_assign_slot
        cmp     #0
        jeq     assign_done

        ; config_nio_write_slot(state, chosen_slot, uri_buf, "rw")
        jsr     load_state
        jsr     pushax
        lda     chosen_slot
        jsr     pusha
        lda     #<_uri_buf
        ldx     #>_uri_buf
        jsr     pushax
        lda     #<mode_rw
        ldx     #>mode_rw
        jsr     _config_nio_write_slot
        cmp     #0
        jeq     assign_done

        ; Preserve the C routine's final refresh. config_nio_write_slot also
        ; invalidates the cache, so this normally resolves from the new page.
        jsr     load_state
        jsr     _config_nio_refresh_slots
assign_done:
        rts

load_browse_path:
        jsr     load_state
        clc
        adc     #STATE_BROWSE_PATH
        pha
        txa
        adc     #0
        tax
        pla
        rts

        .rodata
mode_rw:
        .byte   "rw", 0

        .bss
chosen_slot: .res 1
