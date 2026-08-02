; void draw_slot_rows(config_nio_state_t *state)

        .export _draw_slot_rows

        .import OSWRCH
        .import _gotoxy
        .import _config_nio_bbc_put_fixed
        .import _config_nio_bbc_put_tail
        .import _config_nio_bbc_slot_get
        .import _config_nio_store_buf
        .import _put_slot_index
        .import _selected_slot
        .import _slots_focus
        .import pusha, pushax
        .importzp ptr1

        .include "config_nio_layout.inc"

STATE_SLOT_START = 1
SLOT_URI         = 1

        .code

_draw_slot_rows:
        sta     ptr1
        stx     ptr1+1
        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        sta     slot_start
        lda     #0
        sta     row_index

slot_row_loop:
        ldx     #CONFIG_NIO_BBC_SLOTS_SLOTS_X
        lda     row_index
        clc
        adc     #CONFIG_NIO_BBC_SLOTS_SLOTS_Y
        jsr     goto_xy
        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_CLEAR_WIDTH
        jsr     write_spaces

        ldx     #CONFIG_NIO_BBC_SLOTS_SLOTS_X
        lda     row_index
        clc
        adc     #CONFIG_NIO_BBC_SLOTS_SLOTS_Y
        jsr     goto_xy
        lda     _slots_focus
        beq     slot_not_selected
        lda     row_index
        cmp     _selected_slot
        bne     slot_not_selected
        lda     #'>'
        bne     write_slot_marker
slot_not_selected:
        lda     #' '
write_slot_marker:
        jsr     OSWRCH
        lda     #' '
        jsr     OSWRCH
        lda     slot_start
        clc
        adc     row_index
        jsr     _put_slot_index
        lda     #' '
        jsr     OSWRCH

        lda     row_index
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_bbc_slot_get
        cmp     #0
        beq     empty_slot_row
        lda     #<(_config_nio_store_buf+SLOT_URI)
        ldx     #>(_config_nio_store_buf+SLOT_URI)
        jsr     pushax
        lda     #CONFIG_NIO_BBC_SLOTS_SLOTS_URI_WIDTH
        jsr     _config_nio_bbc_put_tail
        jmp     next_slot_row

empty_slot_row:
        lda     #0
        tax
        jsr     pushax
        lda     #CONFIG_NIO_BBC_SLOTS_SLOTS_URI_WIDTH
        jsr     _config_nio_bbc_put_fixed

next_slot_row:
        inc     row_index
        lda     row_index
        cmp     #CONFIG_NIO_BBC_SLOTS_SLOTS_COUNT
        bne     slot_row_loop
        rts

goto_xy:
        pha
        txa
        jsr     pusha
        pla
        jmp     _gotoxy

write_spaces:
        tax
        lda     #' '
write_space_loop:
        jsr     OSWRCH
        dex
        bne     write_space_loop
        rts

        .bss
slot_start: .res 1
row_index:  .res 1
