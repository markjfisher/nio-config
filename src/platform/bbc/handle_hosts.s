; ===========================================================================
; uint8_t handle_hosts(config_nio_state_t *state, int key)
;
; cc65 fastcall entry:
;
;   A       = key low byte
;   X       = key high byte, ignored because key comes from cgetc()
;   c_sp+0  = state low
;   c_sp+1  = state high
;
; The stacked state pointer is removed by incsp2 on every return.
; ===========================================================================

.macpack longbranch

.export _handle_hosts

.importzp ptr1

.import pusha
.import incsp2

.import _gotoxy
.import _cputc
.import _cgetc

.import _edit_host
.import _clear_host
.import _fetch_browse_page
.import load_state, restore_saved_state_ptr

.import _selected_host
.import _hosts_start
.import _browse_host
.import _browse_start
.import _browse_page_depth
.import _current_screen

.include "config_nio_layout.inc"
.include "bbc_keycodes.inc"
.include "config_nio_host_table.inc"

BBC_HOST_PAGE_ROWS   = CONFIG_NIO_BBC_HOSTS_ROWS_COUNT
LAST_HOST_PAGE_START = ((CONFIG_NIO_BBC_HOST_MAX - 1) / BBC_HOST_PAGE_ROWS) * BBC_HOST_PAGE_ROWS
SCREEN_BROWSE        = 1

; ---------------------------------------------------------------------------
; External BBC config_nio_state_t offsets
; ---------------------------------------------------------------------------

STATE_HOST_COUNT   = 0
STATE_BROWSE_PATH  = 9

.segment "CODE"

_handle_hosts:
        sta     saved_key

        ; Cursor codes must be checked before ASCII case folding.
        lda     saved_key

        cmp     #CH_CURS_UP
        jeq     host_up

        cmp     #CH_CURS_DOWN
        jeq     host_down

        cmp     #CH_CURS_LEFT
        jeq     host_previous_page

        cmp     #CH_CURS_RIGHT
        jeq     host_next_page

        ; Fold upper case into lower case for command keys.
        ora     #$20

        cmp     #'w'
        jeq     host_up

        cmp     #'s'
        jeq     host_down

        cmp     #'e'
        jeq     host_edit

        cmp     #'d'
        jeq     host_clear

        cmp     #'c'
        jeq     host_clear

        ; Return/newline.
        lda     saved_key
        cmp     #$0D
        jeq     host_enter

        cmp     #$0A
        jeq     host_enter

        jmp     return_false


; ===========================================================================
; Move upward
; ===========================================================================

host_up:
        lda     _selected_host
        jeq     return_false

        sta     old_host
        dec     _selected_host

        ; Crossing above the current visible page requires a complete redraw.
        lda     _selected_host
        cmp     _hosts_start
        jcc     return_true

        ; Both old and new hosts are visible, so update only the markers.
        lda     old_host
        ldx     #' '
        jsr     host_marker

        lda     _selected_host
        ldx     #'>'
        jsr     host_marker

        jmp     return_false


; ===========================================================================
; Move downward
; ===========================================================================

host_down:
        lda     _selected_host
        cmp     #CONFIG_NIO_BBC_HOST_MAX - 1
        jcs     return_false

        sta     old_host
        inc     _selected_host

        ; selected_host - hosts_start >= BBC_HOST_PAGE_ROWS
        ; means the selection moved beyond the visible page.
        lda     _selected_host
        sec
        sbc     _hosts_start
        cmp     #BBC_HOST_PAGE_ROWS
        jcs     return_true

        lda     old_host
        ldx     #' '
        jsr     host_marker

        lda     _selected_host
        ldx     #'>'
        jsr     host_marker

        jmp     return_false

host_down_redraw:
        ; CMP equality and carry both represent selected_host >= page end.
        jmp     return_true


; ===========================================================================
; Move to first host page
; ===========================================================================

host_previous_page:
        lda     _hosts_start
        jeq     return_false

        lda     #0
        sta     _hosts_start

        ; If the selected host was on a later page, move selection to host 0.
        lda     _selected_host
        cmp     #BBC_HOST_PAGE_ROWS
        bcc     previous_page_done

        lda     #0
        sta     _selected_host

previous_page_done:
        jmp     return_true


; ===========================================================================
; Move to final host page
; ===========================================================================

host_next_page:
        lda     _hosts_start
        cmp     #LAST_HOST_PAGE_START
        jcs     return_false

        lda     #LAST_HOST_PAGE_START
        sta     _hosts_start

        ; If selection was on the first page, select the first host of the
        ; final page.
        lda     _selected_host
        cmp     #BBC_HOST_PAGE_ROWS
        bcs     next_page_done

        lda     #LAST_HOST_PAGE_START
        sta     _selected_host

next_page_done:
        jmp     return_true


; ===========================================================================
; Edit selected host
; ===========================================================================

host_edit:
        jsr     load_state
        jsr     _edit_host

        ; edit_host() returns void; this handler always requests a redraw.
        jmp     return_true


; ===========================================================================
; Delete/clear selected host
; ===========================================================================

host_clear:
        jsr     load_state
        jsr     _clear_host

        ; clear_host() returns void; this handler always requests a redraw.
        jmp     return_true


; ===========================================================================
; Enter selected host and switch to browse screen
; ===========================================================================

host_enter:
        jsr     restore_saved_state_ptr

        ; Only configured hosts may be opened.
        lda     _selected_host
        ldy     #STATE_HOST_COUNT
        cmp     (ptr1),y
        jcs     return_false

        sta     _browse_host

        ; state->browse_path[0] = 0
        lda     #0
        ldy     #STATE_BROWSE_PATH
        sta     (ptr1),y

        ; browse_start = 0
        sta     _browse_start
        sta     _browse_start+1

        ; reset_browse_pages()
        sta     _browse_page_depth

        jsr     load_state
        jsr     _fetch_browse_page

        cmp     #0
        beq     browse_fetch_failed

        lda     #SCREEN_BROWSE
        sta     _current_screen

        jmp     return_true

; TODO: better error here, this makes it look like it's hung
browse_fetch_failed:
        jsr     _cgetc

        jmp     return_true


; ===========================================================================
; Host marker
;
; Entry:
;
;   A = absolute host index
;   X = marker character, normally '>' or ' '
;
; The caller only invokes this when the host is on the visible page.
;
; Equivalent to:
;
;   gotoxy(CONFIG_NIO_BBC_HOSTS_ROWS_X,
;          CONFIG_NIO_BBC_HOSTS_ROWS_Y + host - hosts_start);
;   cputc(marker);
; ===========================================================================

host_marker:
        stx     marker_char

        sec
        sbc     _hosts_start
        clc
        adc     #CONFIG_NIO_BBC_HOSTS_ROWS_Y
        pha                             ; preserve calculated y

        lda     #CONFIG_NIO_BBC_HOSTS_ROWS_X
        jsr     pusha                   ; stacked x argument

        pla                             ; fastcall y argument
        jsr     _gotoxy

        lda     marker_char
        jmp     _cputc


; ===========================================================================
; Shared returns
; ===========================================================================

return_false:
        lda     #0
        jmp     incsp2

return_true:
        lda     #1
        jmp     incsp2


; ===========================================================================
; Non-reentrant scratch
; ===========================================================================

.segment "BSS"

saved_key:
        .res    1

old_host:
        .res    1

marker_char:
        .res    1
