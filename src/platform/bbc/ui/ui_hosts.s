; Hosts-page navigation for the BBC UI.

.export _clear_host
.export _edit_host
.export _handle_hosts
.export _prompt_host
.export _show_hosts

.import _browse_host
.import _browse_page_depth
.import _browse_start
.import _config_nio_bbc_edit_buf
.import _config_nio_bbc_edit_cap
.import _config_nio_bbc_edit_line
.import _config_nio_bbc_edit_width
.import _config_nio_bbc_edit_x
.import _config_nio_bbc_edit_y
.import _config_nio_bbc_host_clear
.import _config_nio_bbc_host_get
.import _config_nio_bbc_host_set
.import _config_nio_bbc_load_template
.import _config_nio_bbc_put_fixed
.import _config_nio_bbc_put_tail
.import _config_nio_save_hosts
.import _config_nio_store_buf
.import _current_screen
.import _fetch_browse_page
.import _hosts_start
.import _selected_host
.import action_host_count
.import call_high
.import display_host_count
.import goto_xy
.import host_index
.import host_marker_char
.import host_prompt
.import host_row_index
.import host_saved_key
.import hosts_template
.import load_state
.import old_host
.import OSWRCH
.import restore_saved_state_ptr
.import return_false
.import return_true
.import write_spaces

.importzp c_sp
.importzp ptr1

.import pusha
.import pushax
.import incsp2

.import _cgetc
.import _cputc
.import _cputs
.import _gotoxy

.include "../bbc_keycodes.inc"
.include "../config_nio_layout.inc"
.include "../config_nio_host_table.inc"

.macpack longbranch

BBC_HOST_PAGE_ROWS      = CONFIG_NIO_BBC_HOSTS_ROWS_COUNT
LAST_HOST_PAGE_START    = ((CONFIG_NIO_BBC_HOST_MAX - 1) / BBC_HOST_PAGE_ROWS) * BBC_HOST_PAGE_ROWS
SCREEN_BROWSE           = 1

HOST_MAX                = CONFIG_NIO_BBC_HOST_MAX
BBC_EDIT_BUF_SIZE       = CONFIG_NIO_BBC_HOST_SIZE
BBC_HOST_ROW_WIDTH      = CONFIG_NIO_BBC_HOSTS_ROWS_URI_WIDTH + 4
BBC_HOST_TEXT_X         = CONFIG_NIO_BBC_HOSTS_ROWS_X + 4

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


; ---------------------------------------------------------------------------
; External BBC config_nio_state_t offsets
; ---------------------------------------------------------------------------

STATE_HOST_COUNT   = 0
STATE_BROWSE_PATH  = 9

.segment "CODE"

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

_handle_hosts:
        sta     host_saved_key

        ; Cursor codes must be checked before ASCII case folding.
        lda     host_saved_key

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
        lda     host_saved_key
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
        stx     host_marker_char

        sec
        sbc     _hosts_start
        clc
        adc     #CONFIG_NIO_BBC_HOSTS_ROWS_Y
        pha                             ; preserve calculated y

        lda     #CONFIG_NIO_BBC_HOSTS_ROWS_X
        jsr     pusha                   ; stacked x argument

        pla                             ; fastcall y argument
        jsr     _gotoxy

        lda     host_marker_char
        jmp     _cputc

; ===========================================================================
; Non-reentrant scratch
; ===========================================================================


; void show_hosts()
; NOTE: state is now managed directly in uint16_t saved_state, so not a param
_show_hosts:
        lda     _selected_host
        cmp     _hosts_start
        bcc     select_host_page
        sec
        sbc     _hosts_start
        cmp     #CONFIG_NIO_BBC_HOSTS_ROWS_COUNT
        bcc     host_page_ready
select_host_page:
        lda     _selected_host
        cmp     #CONFIG_NIO_BBC_HOSTS_ROWS_COUNT
        bcc     first_host_page
        lda     #CONFIG_NIO_BBC_HOSTS_ROWS_COUNT
        bne     store_host_page
first_host_page:
        lda     #0
store_host_page:
        sta     _hosts_start

host_page_ready:
        jsr     restore_saved_state_ptr
        ldy     #STATE_HOST_COUNT
        lda     (ptr1),y
        sta     display_host_count

        lda     #<hosts_template
        ldx     #>hosts_template
        jsr     _config_nio_bbc_load_template
        lda     #0
        sta     host_row_index

host_row_loop:
        ldx     #CONFIG_NIO_BBC_HOSTS_ROWS_X
        lda     host_row_index
        clc
        adc     #CONFIG_NIO_BBC_HOSTS_ROWS_Y
        jsr     goto_xy

        lda     _hosts_start
        clc
        adc     host_row_index
        sta     host_index
        cmp     #HOST_MAX
        bcc     draw_host_row

        lda     #0
        tax
        jsr     pushax
        lda     #BBC_HOST_ROW_WIDTH
        jsr     _config_nio_bbc_put_fixed
        jmp     next_host_row

draw_host_row:
        cmp     _selected_host
        bne     host_not_selected
        lda     #'>'
        bne     write_host_marker
host_not_selected:
        lda     #' '
write_host_marker:
        jsr     OSWRCH

        lda     host_index
        cmp     #10
        bcc     one_digit_host
        lda     #'1'
        jsr     OSWRCH
        lda     host_index
        sec
        sbc     #10
        bcs     write_host_digit
one_digit_host:
        pha
        lda     #' '
        jsr     OSWRCH
        pla
write_host_digit:
        clc
        adc     #'0'
        jsr     OSWRCH
        lda     #' '
        jsr     OSWRCH

        lda     host_index
        cmp     display_host_count
        bcs     empty_host_value
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     pushax
        lda     #BBC_EDIT_BUF_SIZE
        ldx     #0
        jsr     _config_nio_bbc_host_get
        cmp     #0
        beq     empty_host_value

        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     pushax
        lda     #CONFIG_NIO_BBC_HOSTS_ROWS_URI_WIDTH
        jsr     _config_nio_bbc_put_tail
        jmp     next_host_row

empty_host_value:
        lda     #0
        tax
        jsr     pushax
        lda     #CONFIG_NIO_BBC_HOSTS_ROWS_URI_WIDTH
        jsr     _config_nio_bbc_put_fixed

next_host_row:
        inc     host_row_index
        lda     host_row_index
        cmp     #CONFIG_NIO_BBC_HOSTS_ROWS_COUNT
        beq     hosts_drawn
        jmp     host_row_loop
hosts_drawn:
        rts

; void edit_host(config_nio_state_t *state)
_edit_host:
        lda     _selected_host
        cmp     #HOST_MAX
        bcc     edit_host_valid
        rts

edit_host_valid:
        cmp     _hosts_start
        bcc     redraw_before_edit
        sec
        sbc     _hosts_start
        cmp     #CONFIG_NIO_BBC_HOSTS_ROWS_COUNT
        bcc     prepare_host_edit
redraw_before_edit:
        jsr     load_state
        jsr     _show_hosts

prepare_host_edit:
        jsr     restore_saved_state_ptr
        ldy     #STATE_HOST_COUNT
        lda     _selected_host
        cmp     (ptr1),y
        bcs     new_host_value

        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     pushax
        lda     #BBC_EDIT_BUF_SIZE
        ldx     #0
        jsr     _config_nio_bbc_host_get
        jmp     prompt_host_value

new_host_value:
        lda     #0
        sta     _config_nio_store_buf

prompt_host_value:
        jsr     _prompt_host
        stx     call_high
        ora     call_high
        beq     edit_host_done
        lda     _config_nio_store_buf
        beq     edit_host_done

        lda     _selected_host
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_bbc_host_set

        jsr     restore_saved_state_ptr
        ldy     #STATE_HOST_COUNT
        lda     _selected_host
        cmp     (ptr1),y
        bcc     save_edited_hosts
        clc
        adc     #1
        sta     (ptr1),y
save_edited_hosts:
        jsr     load_state
        jsr     _config_nio_save_hosts
edit_host_done:
        rts

; void clear_host(config_nio_state_t *state)
_clear_host:
        jsr     restore_saved_state_ptr
        ldy     #STATE_HOST_COUNT
        lda     (ptr1),y
        sta     action_host_count
        lda     _selected_host
        cmp     action_host_count
        bcc     clear_host_valid
        rts

clear_host_valid:
        sta     host_index
shift_host_loop:
        lda     host_index
        clc
        adc     #1
        cmp     action_host_count
        bcs     finish_host_shift
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     pushax
        lda     #BBC_EDIT_BUF_SIZE
        ldx     #0
        jsr     _config_nio_bbc_host_get
        cmp     #0
        beq     next_host_shift

        lda     host_index
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_bbc_host_set
next_host_shift:
        inc     host_index
        jmp     shift_host_loop

finish_host_shift:
        dec     action_host_count
        jsr     restore_saved_state_ptr
        ldy     #STATE_HOST_COUNT
        lda     action_host_count
        sta     (ptr1),y
        jsr     _config_nio_bbc_host_clear

        lda     _selected_host
        beq     save_cleared_hosts
        cmp     action_host_count
        bcc     save_cleared_hosts
        dec     _selected_host
save_cleared_hosts:
        jsr     load_state
        jsr     _config_nio_save_hosts
        rts


; int prompt_host(void)
;
; Uses the fixed:
;   label = "Host"
;   buf   = edit_buf
;   cap   = BBC_EDIT_BUF_SIZE
;
; Returns the result from config_nio_bbc_edit_line() in AX.

_prompt_host:

        ; y = CONFIG_NIO_BBC_HOSTS_ROWS_Y
        ;     + selected_host
        ;     - hosts_start
        clc
        lda     #CONFIG_NIO_BBC_HOSTS_ROWS_Y
        adc     _selected_host
        sec
        sbc     _hosts_start
        sta     _config_nio_bbc_edit_y


        ;; Equivalent of
        ;; clear_field(BBC_HOST_TEXT_X, y, HOST_EDIT_WIDTH)

        ;; gotoxy(BBC_HOST_TEXT_X, _config_nio_bbc_edit_y)
        jsr     goto_x_y

        ;; config_nio_bbc_put_fixed("", HOST_EDIT_WIDTH);
        lda     #0
        tax
        jsr     pushax                          ; null pointer just prints spaces as required
        lda     #HOST_EDIT_WIDTH
        jsr     _config_nio_bbc_put_fixed

        ;; gotoxy(BBC_HOST_TEXT_X, _config_nio_bbc_edit_y)
        jsr     goto_x_y


        ; ; clear_field(BBC_HOST_TEXT_X, y, HOST_EDIT_WIDTH)
        ; lda     #BBC_HOST_TEXT_X
        ; jsr     pusha

        ; lda     _config_nio_bbc_edit_y
        ; jsr     pusha

        ; lda     #HOST_EDIT_WIDTH
        ; jsr     _clear_field

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


goto_x_y:
        lda     #BBC_HOST_TEXT_X
        jsr     pusha
        lda     _config_nio_bbc_edit_y
        jmp     _gotoxy


