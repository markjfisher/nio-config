; ===========================================================================
; uint8_t handle_browse(config_nio_state_t *state, int key)
;
; cc65 fastcall entry:
;
;   A       = key low byte
;   X       = key high byte, ignored because key comes from cgetc()
;   c_sp+0  = state low
;   c_sp+1  = state high
;
; The stacked state pointer is removed through incsp2 on every return.
; ===========================================================================

.macpack longbranch

.export _handle_browse

.importzp c_sp
.importzp ptr1

.import pusha
.import pushax
.import incsp2

.import _gotoxy
.import _cputc

.import _config_nio_bbc_entry_get
.import _config_nio_bbc_parent_path
.import _config_nio_bbc_enter_dir

.import _fetch_browse_page
.import _fetch_next_browse_page
.import _fetch_previous_browse_page
.import _assign_selected_file

.import _selected_entry
.import _browse_start
.import _browse_more
.import _browse_page_depth

.include "config_nio_layout.inc"
.include "constants.inc"

; ---------------------------------------------------------------------------
; config_nio_state_t offsets, BBC external-state model
; ---------------------------------------------------------------------------

STATE_ENTRY_COUNT = 5
STATE_BROWSE_PATH = 9


; ---------------------------------------------------------------------------
; config_nio_entry_t layout
;
; typedef struct {
;     uint8_t is_dir;
;     char name[CONFIG_NIO_NAME_MAX + 1];
; } config_nio_entry_t;
; ---------------------------------------------------------------------------

ENTRY_FLAGS       = 0
ENTRY_NAME        = 1
ENTRY_SIZE        = 32

ENTRY_FLAG_DIR            = $01
ENTRY_FLAG_NAME_TRUNCATED = $80


.segment "CODE"

_handle_browse:
        sta     saved_key

        ; Save state independently of the changing C software stack.
        ldy     #1
        lda     (c_sp),y
        sta     saved_state+1
        dey
        lda     (c_sp),y
        sta     saved_state

        ; Cursor codes must be tested before ASCII case folding.
        lda     saved_key

        cmp     #CH_CURS_UP
        jeq     browse_up

        cmp     #CH_CURS_DOWN
        jeq     browse_down

        cmp     #CH_CURS_RIGHT
        jeq     browse_next

        cmp     #CH_CURS_LEFT
        jeq     browse_previous

        ; Fold ASCII uppercase into lowercase.
        ora     #$20

        cmp     #'w'
        jeq     browse_up

        cmp     #'s'
        jeq     browse_down

        cmp     #'u'
        jeq     browse_parent

        cmp     #'a'
        jeq     browse_assign

        ; Return and newline are unchanged by ORA #$20, but use the original
        ; value for clarity.
        lda     saved_key
        cmp     #$0D
        jeq     browse_enter

        cmp     #$0A
        jeq     browse_enter

        jmp     return_false


; ===========================================================================
; Move selection upward
; ===========================================================================

browse_up:
        lda     _selected_entry
        beq     browse_up_at_first

        sta     old_selection
        dec     _selected_entry

        lda     old_selection
        ldx     #' '
        jsr     browse_marker

        lda     _selected_entry
        ldx     #'>'
        jsr     browse_marker

        jmp     return_false


browse_up_at_first:
        ; If this is not the first fetched page, fetch the preceding one.
        lda     _browse_start
        ora     _browse_start+1
        jeq     return_false

        jmp     call_previous_page


; ===========================================================================
; Move selection downward
; ===========================================================================

browse_down:
        ; Test:
        ;
        ;   selected_entry + 1 < state->entry_count
        ;
        jsr     restore_state_ptr

        lda     _selected_entry
        clc
        adc     #1

        ldy     #STATE_ENTRY_COUNT
        cmp     (ptr1),y
        bcc     browse_move_down

        ; At the final visible entry. Advance to the next page when available.
        lda     _browse_more
        jeq     return_false

        jmp     call_next_page


browse_move_down:
        lda     _selected_entry
        sta     old_selection
        inc     _selected_entry

        lda     old_selection
        ldx     #' '
        jsr     browse_marker

        lda     _selected_entry
        ldx     #'>'
        jsr     browse_marker

        jmp     return_false


; ===========================================================================
; Explicit page navigation
; ===========================================================================

browse_next:
        lda     _browse_more
        jeq     return_false

call_next_page:
        jsr     load_state_ax
        jsr     _fetch_next_browse_page

        ; Return the helper's Boolean result directly after removing state.
        jmp     incsp2


browse_previous:
        lda     _browse_start
        ora     _browse_start+1
        jeq     return_false

call_previous_page:
        jsr     load_state_ax
        jsr     _fetch_previous_browse_page

        ; Return the helper's Boolean result directly.
        jmp     incsp2


; ===========================================================================
; Move to parent directory
; ===========================================================================

browse_parent:
        ; config_nio_bbc_parent_path(state->browse_path)
        jsr     load_browse_path_ax
        jsr     _config_nio_bbc_parent_path

        ; browse_start = 0
        lda     #0
        sta     _browse_start
        sta     _browse_start+1

        ; reset_browse_pages()
        sta     _browse_page_depth

        ; The original ignores the fetch result and returns redraw=1.
        jsr     load_state_ax
        jsr     _fetch_browse_page

        jmp     return_true


; ===========================================================================
; Assign currently selected file
; ===========================================================================

browse_assign:
        jsr     load_state_ax
        jsr     _assign_selected_file

        ; assign_selected_file() returns void; the UI always redraws.
        jmp     return_true


; ===========================================================================
; Return/newline action
; ===========================================================================

browse_enter:
        ; Nothing can be selected when entry_count is zero.
        jsr     restore_state_ptr
        ldy     #STATE_ENTRY_COUNT
        lda     (ptr1),y
        jeq     return_false

        ; config_nio_bbc_entry_get(selected_entry, &entry_tmp)
        lda     _selected_entry
        jsr     pusha

        lda     #<entry_tmp
        ldx     #>entry_tmp
        jsr     _config_nio_bbc_entry_get

        ; Failed lookup follows the C "else" path and invokes assignment.
        cmp     #0
        beq     browse_assign

        lda     entry_tmp+ENTRY_FLAGS
        and     #ENTRY_FLAG_DIR
        beq     browse_assign

        ; A truncated directory name cannot safely be entered.
        lda     entry_tmp+ENTRY_FLAGS
        and     #ENTRY_FLAG_NAME_TRUNCATED
        jne     return_true

        ; config_nio_bbc_enter_dir(state->browse_path, entry_tmp.name)
        ;
        ; First argument is pushed; final argument arrives in AX.
        jsr     load_browse_path_ax
        jsr     pushax

        lda     #<entry_tmp+ENTRY_NAME
        ldx     #>entry_tmp+ENTRY_NAME
        jsr     _config_nio_bbc_enter_dir

        ; A failed enter still causes the screen to redraw in the C version.
        cmp     #0
        jeq     return_true

        ; Successful directory change starts pagination again from zero.
        lda     #0
        sta     _browse_start
        sta     _browse_start+1
        sta     _browse_page_depth

        jsr     load_state_ax
        jsr     _fetch_browse_page

        jmp     return_true


; ===========================================================================
; State helpers
; ===========================================================================

; Restore saved_state into zero-page ptr1.
restore_state_ptr:
        lda     saved_state
        sta     ptr1
        lda     saved_state+1
        sta     ptr1+1
        rts


; Return state in AX.
load_state_ax:
        lda     saved_state
        ldx     saved_state+1
        rts


; Return &state->browse_path in AX.
load_browse_path_ax:
        lda     saved_state
        clc
        adc     #STATE_BROWSE_PATH
        sta     browse_path_ptr

        lda     saved_state+1
        adc     #0
        tax

        lda     browse_path_ptr
        rts

; ===========================================================================
; Browse selection marker
;
; Entry:
;
;   A = selected row
;   X = marker character, normally '>' or ' '
;
; Equivalent to:
;
;   gotoxy(CONFIG_NIO_BBC_BROWSE_ROWS_X,
;          CONFIG_NIO_BBC_BROWSE_ROWS_Y + row);
;   cputc(marker);
; ===========================================================================

browse_marker:
        stx     marker_char

        clc
        adc     #CONFIG_NIO_BBC_BROWSE_ROWS_Y
        pha                             ; calculated y

        lda     #CONFIG_NIO_BBC_BROWSE_ROWS_X
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
; Non-reentrant scratch storage
; ===========================================================================

.segment "BSS"

saved_state:
        .res    2

saved_key:
        .res    1

old_selection:
        .res    1

marker_char:
        .res    1

entry_tmp:
        .res    ENTRY_SIZE

browse_path_ptr:
        .res    1
