; void draw_browse(config_nio_state_t *state)
;
; BBC-specific rendering of the host, path, and twelve cached directory rows.
; The external table implementation lets the shared store buffer serve as the
; temporary host/entry record instead of reserving C-stack structures.

        .export _draw_browse

        .import OSWRCH
        .import _gotoxy
        .import _config_nio_bbc_entry_get
        .import _config_nio_bbc_host_get
        .import _config_nio_bbc_load_template
        .import _config_nio_bbc_put_fixed
        .import _config_nio_bbc_put_tail
        .import _config_nio_store_buf
        .import _browse_host
        .import _selected_entry
        .import pusha, pushax
        .importzp ptr1

        .include "config_nio_layout.inc"

STATE_ENTRY_COUNT = 5
STATE_BROWSE_PATH = 9

ENTRY_IS_DIR = 0
ENTRY_NAME   = 1
ENTRY_FLAG_DIR = $01

BBC_EDIT_BUF_SIZE = 97

        .code

_draw_browse:
        sta     state_ptr
        stx     state_ptr+1

        lda     #<browse_template
        ldx     #>browse_template
        jsr     _config_nio_bbc_load_template

        ; Host field. Both output helpers fill the complete field width, so
        ; the separate C clear_field() pass is unnecessary.
        ldx     #CONFIG_NIO_BBC_BROWSE_HOST_X
        lda     #CONFIG_NIO_BBC_BROWSE_HOST_Y
        jsr     goto_xy

        lda     _browse_host
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     pushax
        lda     #BBC_EDIT_BUF_SIZE
        ldx     #0
        jsr     _config_nio_bbc_host_get
        cmp     #0
        beq     empty_host

        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     pushax
        lda     #CONFIG_NIO_BBC_BROWSE_HOST_WIDTH
        jsr     _config_nio_bbc_put_tail
        jmp     draw_path

empty_host:
        lda     #0
        tax
        jsr     pushax
        lda     #CONFIG_NIO_BBC_BROWSE_HOST_WIDTH
        jsr     _config_nio_bbc_put_fixed

draw_path:
        ldx     #CONFIG_NIO_BBC_BROWSE_PATH_X
        lda     #CONFIG_NIO_BBC_BROWSE_PATH_Y
        jsr     goto_xy
        lda     #'/'
        jsr     OSWRCH

        lda     state_ptr
        clc
        adc     #STATE_BROWSE_PATH
        pha
        lda     state_ptr+1
        adc     #0
        tax
        pla
        jsr     pushax
        lda     #CONFIG_NIO_BBC_BROWSE_PATH_WIDTH
        jsr     _config_nio_bbc_put_tail

        lda     #0
        sta     row_index

row_loop:
        ldx     #CONFIG_NIO_BBC_BROWSE_ROWS_X
        lda     row_index
        clc
        adc     #CONFIG_NIO_BBC_BROWSE_ROWS_Y
        jsr     goto_xy

        lda     state_ptr
        sta     ptr1
        lda     state_ptr+1
        sta     ptr1+1
        ldy     #STATE_ENTRY_COUNT
        lda     row_index
        cmp     (ptr1),y
        bcs     empty_row

        lda     row_index
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_bbc_entry_get
        cmp     #0
        beq     empty_row

        lda     row_index
        cmp     _selected_entry
        bne     row_not_selected
        lda     #'>'
        bne     write_marker
row_not_selected:
        lda     #' '
write_marker:
        jsr     OSWRCH

        lda     _config_nio_store_buf+ENTRY_IS_DIR
        and     #ENTRY_FLAG_DIR
        beq     row_not_directory
        lda     #'/'
        bne     write_kind
row_not_directory:
        lda     #' '
write_kind:
        jsr     OSWRCH
        lda     #' '
        jsr     OSWRCH

        lda     #<(_config_nio_store_buf+ENTRY_NAME)
        ldx     #>(_config_nio_store_buf+ENTRY_NAME)
        jsr     pushax
        lda     #CONFIG_NIO_BBC_BROWSE_ROWS_NAME_WIDTH
        jsr     _config_nio_bbc_put_tail
        jmp     next_row

empty_row:
        lda     #0
        tax
        jsr     pushax
        lda     #CONFIG_NIO_BBC_BROWSE_ROWS_CLEAR_WIDTH
        jsr     _config_nio_bbc_put_fixed

next_row:
        inc     row_index
        lda     row_index
        cmp     #CONFIG_NIO_BBC_BROWSE_ROWS_COUNT
        bne     row_loop
        rts

; X = column, A = row. gotoxy() takes its first byte on the C stack and its
; final byte in A, so the hardware stack safely preserves the row around pusha.
goto_xy:
        pha
        txa
        jsr     pusha
        pla
        jmp     _gotoxy

        .rodata
browse_template:
        .byte   "CNBROW", 0

        .bss
state_ptr:      .res 2
row_index:      .res 1
