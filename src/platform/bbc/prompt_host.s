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

.import _current_screen
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

LOCAL_X     = 0
LOCAL_Y     = 1
LOCAL_WIDTH = 2

        ; Allocate three temporary bytes:
        ;
        ; c_sp + 0  x
        ; c_sp + 1  y
        ; c_sp + 2  width
        ;
        jsr     decsp3

        lda     _current_screen
        cmp     #SCREEN_BROWSE
        bne     not_browse


; ---------------------------------------------------------------------------
; Browse-screen setup
; ---------------------------------------------------------------------------

browse:
        ldy     #LOCAL_X
        lda     #CONFIG_NIO_BBC_BROWSE_INPUT_TEXT_X
        sta     (c_sp),y

        iny                             ; LOCAL_Y
        lda     #CONFIG_NIO_BBC_BROWSE_INPUT_Y
        sta     (c_sp),y

        iny                             ; LOCAL_WIDTH
        lda     #BROWSE_EDIT_WIDTH
        sta     (c_sp),y

        ; clear_field(
        ;     CONFIG_NIO_BBC_BROWSE_INPUT_LABEL_X,
        ;     CONFIG_NIO_BBC_BROWSE_INPUT_Y,
        ;     CONFIG_NIO_BBC_BROWSE_INPUT_CLEAR_WIDTH
        ; );
        ;
        ; clear_field is assumed to use cc65 fastcall:
        ;   x and y on the C stack
        ;   width in A
        ;
        lda     #CONFIG_NIO_BBC_BROWSE_INPUT_LABEL_X
        jsr     pusha

        lda     #CONFIG_NIO_BBC_BROWSE_INPUT_Y
        jsr     pusha

        lda     #CONFIG_NIO_BBC_BROWSE_INPUT_CLEAR_WIDTH
        jsr     _clear_field

        ; The original:
        ;
        ;   cputs("Host");
        ;   cputs(":");
        ;   put_fixed("", 1);
        ;
        ; reduces to:
        ;
        ;   cputs("Host: ");
        ;
        lda     #<host_prompt
        ldx     #>host_prompt
        jsr     _cputs

        jmp     clear_input_field


; ---------------------------------------------------------------------------
; Hosts-screen setup
; ---------------------------------------------------------------------------

not_browse:
        ldy     #LOCAL_X
        lda     #BBC_HOST_TEXT_X
        sta     (c_sp),y

        ; y = CONFIG_NIO_BBC_HOSTS_ROWS_Y
        ;     + selected_host
        ;     - hosts_start
        ;
        iny                             ; LOCAL_Y
        clc
        lda     #CONFIG_NIO_BBC_HOSTS_ROWS_Y
        adc     _selected_host
        sec
        sbc     _hosts_start
        sta     (c_sp),y

        iny                             ; LOCAL_WIDTH
        lda     #HOST_EDIT_WIDTH
        sta     (c_sp),y

        ; In this branch:
        ;
        ;   clear_x     = x
        ;   clear_width = width
        ;
        ; So the initial clear is identical to the input-field clear below.


; ---------------------------------------------------------------------------
; Clear the actual editable field
; ---------------------------------------------------------------------------

clear_input_field:
        ; clear_field(x, y, width)
        ;
        ; Start with locals at:
        ;
        ;   +0 x
        ;   +1 y
        ;   +2 width
        ;
        ; After pushing x:
        ;
        ;   +0 pushed x
        ;   +1 local x
        ;   +2 local y
        ;   +3 local width
        ;
        ldy     #LOCAL_X
        lda     (c_sp),y
        jsr     pusha

        ; After pushing x, local y is now at offset 2.
        ldy     #LOCAL_Y + 1
        lda     (c_sp),y
        jsr     pusha

        ; After pushing x and y, local width is now at offset 4.
        ldy     #LOCAL_WIDTH + 2
        lda     (c_sp),y
        jsr     _clear_field

        ; _clear_field removes its two stack arguments, so our local frame is
        ; back at offsets 0..2 here.


; ---------------------------------------------------------------------------
; Configure and invoke the line editor
; ---------------------------------------------------------------------------

        ; config_nio_bbc_edit_buf = edit_buf;
        lda     #<_edit_buf
        sta     _config_nio_bbc_edit_buf
        lda     #>_edit_buf
        sta     _config_nio_bbc_edit_buf+1

        ; config_nio_bbc_edit_cap = BBC_EDIT_BUF_SIZE;
        lda     #BBC_EDIT_BUF_SIZE
        sta     _config_nio_bbc_edit_cap

        ; Copy x, y and width from the temporary frame.
        ldy     #LOCAL_X
        lda     (c_sp),y
        sta     _config_nio_bbc_edit_x

        iny                             ; LOCAL_Y
        lda     (c_sp),y
        sta     _config_nio_bbc_edit_y

        iny                             ; LOCAL_WIDTH
        lda     (c_sp),y
        sta     _config_nio_bbc_edit_width

        jsr     _config_nio_bbc_edit_line

        ; Preserve the returned int in AX on the hardware stack.
        ;
        ; Keep it there until after any final clear and after incsp3,
        ; because those operations may clobber A/X.
        pha                             ; result low byte
        txa
        pha                             ; result high byte

        lda     _current_screen
        cmp     #SCREEN_BROWSE
        bne     finish


; ---------------------------------------------------------------------------
; Browse mode clears the whole prompt area after editing
; ---------------------------------------------------------------------------

        ; clear_field(
        ;     CONFIG_NIO_BBC_BROWSE_INPUT_LABEL_X,
        ;     CONFIG_NIO_BBC_BROWSE_INPUT_Y,
        ;     CONFIG_NIO_BBC_BROWSE_INPUT_CLEAR_WIDTH
        ; );
        ;
        lda     #CONFIG_NIO_BBC_BROWSE_INPUT_LABEL_X
        jsr     pusha

        lda     #CONFIG_NIO_BBC_BROWSE_INPUT_Y
        jsr     pusha

        lda     #CONFIG_NIO_BBC_BROWSE_INPUT_CLEAR_WIDTH
        jsr     _clear_field


; ---------------------------------------------------------------------------
; Restore frame and returned result
; ---------------------------------------------------------------------------

finish:
        jsr     incsp3

        pla                             ; result high byte
        tax
        pla                             ; result low byte
        rts

.endproc


.segment "RODATA"

host_prompt:
        .byte   "Host: ", 0