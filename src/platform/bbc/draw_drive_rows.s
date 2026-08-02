; void draw_drive_rows(config_nio_state_t *state)
;
; Draw the four persistent or transient drive mappings. The external state
; implementation lets the shared store buffer hold both the mapping and slot
; records, avoiding two C-stack structures.

        .export _draw_drive_rows

        .import OSWRCH
        .import _gotoxy
        .import _config_nio_bbc_mapping_get
        .import _config_nio_bbc_put_basename
        .import _config_nio_bbc_put_fixed
        .import _config_nio_read_slot
        .import _config_nio_store_buf
        .import _put_slot_index
        .import _runtime_offsets
        .import _selected_drive
        .import _slots_focus
        .import _uri_buf
        .import pusha, pushax
        .importzp ptr1

        .include "config_nio_layout.inc"

MAPPING_VALID    = 0
MAPPING_SLOT     = 1
MAPPING_READONLY = 2

SLOT_ENABLED = 0
SLOT_URI     = 1

BBC_DRIVE_COUNT       = 4
BBC_RUNTIME_NAME_WIDTH = 19

        .code

_draw_drive_rows:
        lda     #0
        sta     drive_index

drive_loop:
        ldx     #CONFIG_NIO_BBC_SLOTS_DRIVES_X
        lda     drive_index
        clc
        adc     #CONFIG_NIO_BBC_SLOTS_DRIVES_Y
        jsr     goto_xy

        lda     _slots_focus
        bne     drive_not_selected
        lda     drive_index
        cmp     _selected_drive
        bne     drive_not_selected
        lda     #'>'
        bne     write_marker
drive_not_selected:
        lda     #' '
write_marker:
        jsr     OSWRCH
        lda     #'D'
        jsr     OSWRCH
        lda     drive_index
        clc
        adc     #'0'
        jsr     OSWRCH
        lda     #' '
        jsr     OSWRCH

        lda     drive_index
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_bbc_mapping_get
        cmp     #0
        beq     runtime_mapping
        lda     _config_nio_store_buf+MAPPING_VALID
        beq     runtime_mapping

        lda     _config_nio_store_buf+MAPPING_SLOT
        sta     mapping_slot
        lda     _config_nio_store_buf+MAPPING_READONLY
        sta     mapping_readonly

        lda     #'S'
        jsr     OSWRCH
        lda     mapping_slot
        jsr     _put_slot_index
        lda     #' '
        jsr     OSWRCH
        lda     mapping_readonly
        beq     writable_mapping
        lda     #'R'
        bne     write_mode
writable_mapping:
        lda     #'W'
write_mode:
        jsr     OSWRCH
        lda     #' '
        jsr     OSWRCH

        lda     mapping_slot
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_read_slot
        cmp     #0
        beq     empty_slot_name
        lda     _config_nio_store_buf+SLOT_ENABLED
        beq     empty_slot_name

        lda     #<(_config_nio_store_buf+SLOT_URI)
        ldx     #>(_config_nio_store_buf+SLOT_URI)
        jsr     pushax
        jsr     slot_name_width
        jsr     _config_nio_bbc_put_basename
        jmp     next_drive

empty_slot_name:
        lda     #0
        tax
        jsr     pushax
        jsr     slot_name_width
        jsr     _config_nio_bbc_put_fixed
        jmp     next_drive

runtime_mapping:
        ldy     drive_index
        lda     _runtime_offsets,y
        clc
        adc     #<_uri_buf
        sta     ptr1
        lda     #>_uri_buf
        adc     #0
        sta     ptr1+1
        ldy     #0
        lda     (ptr1),y
        beq     no_mapping

        lda     #'B'
        jsr     OSWRCH
        lda     #'O'
        jsr     OSWRCH
        jsr     OSWRCH
        lda     #'T'
        jsr     OSWRCH
        lda     #' '
        jsr     OSWRCH
        lda     ptr1
        ldx     ptr1+1
        jsr     pushax
        lda     #BBC_RUNTIME_NAME_WIDTH
        jsr     _config_nio_bbc_put_basename
        jmp     next_drive

no_mapping:
        lda     #'-'
        jsr     OSWRCH
        jsr     OSWRCH
        lda     #0
        tax
        jsr     pushax
        lda     #CONFIG_NIO_BBC_SLOTS_DRIVES_EMPTY_WIDTH
        jsr     _config_nio_bbc_put_fixed

next_drive:
        inc     drive_index
        lda     drive_index
        cmp     #BBC_DRIVE_COUNT
        beq     drive_done
        jmp     drive_loop
drive_done:
        rts

; The slot prefix gains one character at 10 and again at 100, so reduce the
; basename field by the same amount. Returns the width in A.
slot_name_width:
        lda     mapping_slot
        cmp     #10
        bcs     two_digits
        lda     #CONFIG_NIO_BBC_SLOTS_DRIVES_BASENAME_WIDTH
        rts
two_digits:
        cmp     #100
        bcs     three_digits
        lda     #(CONFIG_NIO_BBC_SLOTS_DRIVES_BASENAME_WIDTH-1)
        rts
three_digits:
        lda     #(CONFIG_NIO_BBC_SLOTS_DRIVES_BASENAME_WIDTH-2)
        rts

; X = column, A = row.
goto_xy:
        pha
        txa
        jsr     pusha
        pla
        jmp     _gotoxy

        .bss
drive_index:      .res 1
mapping_slot:     .res 1
mapping_readonly: .res 1
