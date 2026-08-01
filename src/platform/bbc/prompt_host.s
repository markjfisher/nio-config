; int prompt_host(void)
;
; Uses the fixed:
;   label = "Host"
;   buf   = edit_buf
;   cap   = BBC_EDIT_BUF_SIZE
;
; Returns the result from config_nio_bbc_edit_line() in AX.

.export _prompt_host

.importzp c_sp

.import pusha
.import decsp3
.import incsp3

.import _cputs
.import _clear_field
.import _config_nio_bbc_edit_line

.import _selected_host
.import _hosts_start

.import _config_nio_store_buf
.import _config_nio_bbc_edit_buf
.import _config_nio_bbc_edit_cap
.import _config_nio_bbc_edit_x
.import _config_nio_bbc_edit_y
.import _config_nio_bbc_edit_width

.include "config_nio_layout.inc"

BBC_EDIT_BUF_SIZE       := 97
SCREEN_HOSTS            := 0
SCREEN_BROWSE           := 1
SCREEN_SLOTS            := 2
BBC_HOST_TEXT_X         := CONFIG_NIO_BBC_HOSTS_ROWS_X + 4

_edit_buf = _config_nio_store_buf

; Clamp the two possible edit widths at assembly time.
;
; This replaces:
;
;   if (cap <= width)
;       width = cap - 1;
;
.if CONFIG_NIO_BBC_BROWSE_INPUT_WIDTH >= BBC_EDIT_BUF_SIZE
BROWSE_EDIT_WIDTH = BBC_EDIT_BUF_SIZE - 1
.else
BROWSE_EDIT_WIDTH = CONFIG_NIO_BBC_BROWSE_INPUT_WIDTH
.endif

.if CONFIG_NIO_BBC_HOSTS_ROWS_URI_WIDTH >= BBC_EDIT_BUF_SIZE
HOST_EDIT_WIDTH = BBC_EDIT_BUF_SIZE - 1
.else
HOST_EDIT_WIDTH = CONFIG_NIO_BBC_HOSTS_ROWS_URI_WIDTH
.endif

.assert BROWSE_EDIT_WIDTH > 0, error, "Browse edit width is zero"
.assert HOST_EDIT_WIDTH > 0, error, "Host edit width is zero"


.segment "CODE"

.proc _prompt_host

        ; y = CONFIG_NIO_BBC_HOSTS_ROWS_Y
        ;     + selected_host
        ;     - hosts_start
        clc
        lda     #CONFIG_NIO_BBC_HOSTS_ROWS_Y
        adc     _selected_host
        sec
        sbc     _hosts_start
        sta     _config_nio_bbc_edit_y

        ; clear_field(BBC_HOST_TEXT_X, y, HOST_EDIT_WIDTH)
        lda     #BBC_HOST_TEXT_X
        jsr     pusha

        lda     _config_nio_bbc_edit_y
        jsr     pusha

        lda     #HOST_EDIT_WIDTH
        jsr     _clear_field

        ; Configure the fixed editor values.
        lda     #<_config_nio_store_buf
        sta     _config_nio_bbc_edit_buf
        lda     #>_config_nio_store_buf
        sta     _config_nio_bbc_edit_buf+1

        lda     #BBC_EDIT_BUF_SIZE
        sta     _config_nio_bbc_edit_cap

        lda     #BBC_HOST_TEXT_X
        sta     _config_nio_bbc_edit_x

        lda     #HOST_EDIT_WIDTH
        sta     _config_nio_bbc_edit_width

        ; Return config_nio_bbc_edit_line() directly.
        jmp     _config_nio_bbc_edit_line

.endproc


.segment "RODATA"

host_prompt:
        .byte   "Host: ", 0