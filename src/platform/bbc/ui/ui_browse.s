; Browse-page navigation for the BBC UI.

.export _assign_selected_file
.export _draw_browse
.export _fetch_browse_page
.export _fetch_next_browse_page
.export _fetch_previous_browse_page
.export _handle_browse
.export _prompt_assign_slot


.import _assign_slot_start
.import _browse_host
.import _browse_more
.import _browse_next
.import _browse_page_depth
.import _browse_page_stack
.import _browse_start
.import _config_nio_appstore_buf
.import _config_nio_bbc_enter_dir
.import _config_nio_bbc_entry_get
.import _config_nio_bbc_host_get
.import _config_nio_bbc_invalidate_slot_cache
.import _config_nio_bbc_load_template
.import _config_nio_bbc_parent_path
.import _config_nio_bbc_put_fixed
.import _config_nio_bbc_put_tail
.import _config_nio_bbc_slot_get
.import _config_nio_compose_uri
.import _config_nio_refresh_slots
.import _config_nio_store_buf
.import _config_nio_write_slot
.import _fnsvc_config_nio_list_directory_page
.import _key_is_next_page
.import _key_is_previous_page
.import _put_slot_index
.import _selected_entry
.import _selected_slot
.import _uri_buf
.import assign_hint
.import assign_marker_char
.import assign_row_index
.import assign_state_ptr
.import assign_title
.import browse_draw_state_ptr
.import browse_marker_char
.import browse_old_selection
.import browse_path_low
.import browse_path_ptr
.import browse_row_index
.import browse_saved_key
.import browse_template
.import chosen_slot
.import clear_row
.import empty_string
.import entry_tmp
.import fetch_start
.import goto_xy
.import key_value
.import load_state
.import mode_rw
.import more
.import next_start
.import old_slot
.import old_start
.import OSWRCH
.import prompt_slot
.import remaining
.import restore_saved_state_ptr
.import return_false
.import return_true
.import saved_slot_start
.import slot_out_ptr
.import write_spaces

.import incsp2
.import popax
.import pusha
.import pushax
.import return0
.import return1

.import _cgetc
.import _cputc
.import _cputs
.import _gotoxy

.importzp ptr1

.include "../config_nio_layout.inc"
.include "../config_nio_host_table.inc"
.include "../bbc_keycodes.inc"

.macpack longbranch

STATE_ENTRY_COUNT       = 5
STATE_ENTRIES_TRUNCATED = 8
STATE_BROWSE_PATH       = 9

STATE_SLOT_START        = 1
SLOT_URI                = 1
FNCTL_MAX_UNITS         = 8

BBC_BROWSE_PAGE_STACK   = 6
BBC_BROWSE_PAGE_ROWS    = CONFIG_NIO_BBC_BROWSE_ROWS_COUNT
BBC_EDIT_BUF_SIZE       = CONFIG_NIO_BBC_HOST_SIZE
BBC_URI_WORK_MAX        = 129

; ---------------------------------------------------------------------------
; config_nio_entry_t layout
;
; typedef struct {
;     uint8_t is_dir;
;     char name[CONFIG_NIO_NAME_MAX + 1];
; } config_nio_entry_t;
; ---------------------------------------------------------------------------

ENTRY_FLAGS                     = 0
ENTRY_NAME                      = 1
ENTRY_IS_DIR                    = 0
ENTRY_SIZE                      = 32
ENTRY_FLAG_DIR                  = $01
ENTRY_FLAG_NAME_TRUNCATED       = $80

.code

; void assign_selected_file(config_nio_state_t *state)
;
; The selected entry is copied into the app-store transfer buffer so the
; shared store buffer remains available for the host string.
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



; int fetch_next_browse_page(config_nio_state_t *state)
_fetch_next_browse_page:
        lda     _browse_more
        bne     :+
        jmp     return0
:
        lda     _browse_start
        sta     old_start
        lda     _browse_start+1
        sta     old_start+1

        lda     _browse_page_depth
        cmp     #BBC_BROWSE_PAGE_STACK
        bcs     set_next_start
        asl     a
        tay
        lda     old_start
        sta     _browse_page_stack,y
        lda     old_start+1
        sta     _browse_page_stack+1,y
        inc     _browse_page_depth

set_next_start:
        lda     _browse_next
        sta     _browse_start
        lda     _browse_next+1
        sta     _browse_start+1
        jsr     load_state
        jsr     _fetch_browse_page
        cmp     #0
        beq     next_failed
        jmp     return1

next_failed:
        lda     old_start
        sta     _browse_start
        lda     old_start+1
        sta     _browse_start+1
        lda     _browse_page_depth
        beq     :+
        dec     _browse_page_depth
:
        jmp     return0

; int fetch_previous_browse_page(config_nio_state_t *state)
_fetch_previous_browse_page:
        lda     _browse_page_depth
        beq     previous_first
        dec     _browse_page_depth
        lda     _browse_page_depth
        asl     a
        tay
        lda     _browse_page_stack,y
        sta     _browse_start
        lda     _browse_page_stack+1,y
        sta     _browse_start+1
        jmp     fetch_previous

previous_first:
        lda     #0
        sta     _browse_start
        sta     _browse_start+1

fetch_previous:
        jsr     load_state
        jsr     _fetch_browse_page
        cmp     #0
        beq     previous_done
        jsr     restore_saved_state_ptr
        ldy     #STATE_ENTRY_COUNT
        lda     (ptr1),y
        beq     previous_done
        sec
        sbc     #1
        sta     _selected_entry
previous_done:
        ; The C API deliberately reports redraw even when the fetch failed.
        jmp     return1


; void draw_browse(config_nio_state_t *state)
;
; BBC-specific rendering of the host, path, and twelve cached directory rows.
; The external table implementation lets the shared store buffer serve as the
; temporary host/entry record instead of reserving C-stack structures.
_draw_browse:
        sta     browse_draw_state_ptr
        stx     browse_draw_state_ptr+1

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

        lda     browse_draw_state_ptr
        clc
        adc     #STATE_BROWSE_PATH
        pha
        lda     browse_draw_state_ptr+1
        adc     #0
        tax
        pla
        jsr     pushax
        lda     #CONFIG_NIO_BBC_BROWSE_PATH_WIDTH
        jsr     _config_nio_bbc_put_tail

        lda     #0
        sta     browse_row_index

row_loop:
        ldx     #CONFIG_NIO_BBC_BROWSE_ROWS_X
        lda     browse_row_index
        clc
        adc     #CONFIG_NIO_BBC_BROWSE_ROWS_Y
        jsr     goto_xy

        lda     browse_draw_state_ptr
        sta     ptr1
        lda     browse_draw_state_ptr+1
        sta     ptr1+1
        ldy     #STATE_ENTRY_COUNT
        lda     browse_row_index
        cmp     (ptr1),y
        bcs     empty_row

        lda     browse_row_index
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_bbc_entry_get
        cmp     #0
        beq     empty_row

        lda     browse_row_index
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
        inc     browse_row_index
        lda     browse_row_index
        cmp     #CONFIG_NIO_BBC_BROWSE_ROWS_COUNT
        bne     row_loop
        rts


; ===========================================================================
; int fetch_browse_page()
;
; cc65 fastcall entry:
;
;   AX = state
;
; Return:
;
;   AX = 1 on success
;   AX = 0 on failure
;
; BBC-specific behaviour:
;
; - config_nio_set_status() is a no-op.
; - host and entry tables are external.
; - fixed BSS scratch replaces all C locals.
; ===========================================================================

_fetch_browse_page:
        ; state->entry_count = 0
        ; state->entries_truncated = 0
        jsr     restore_saved_state_ptr

        lda     #0

        ldy     #STATE_ENTRY_COUNT
        sta     (ptr1),y

        ldy     #STATE_ENTRIES_TRUNCATED
        sta     (ptr1),y


; ---------------------------------------------------------------------------
; config_nio_bbc_host_get(
;     browse_host,
;     config_nio_store_buf,
;     BBC_EDIT_BUF_SIZE);
;
; cc65 fastcall:
;
;   stacked: browse_host, buffer
;   AX:      capacity
; ---------------------------------------------------------------------------

        lda     _browse_host
        jsr     pusha

        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     pushax

        lda     #<BBC_EDIT_BUF_SIZE
        ldx     #>BBC_EDIT_BUF_SIZE
        jsr     _config_nio_bbc_host_get

        cmp     #0
        jeq     return0


; ---------------------------------------------------------------------------
; config_nio_compose_uri(
;     config_nio_store_buf,
;     state->browse_path,
;     "",
;     uri_buf,
;     BBC_URI_WORK_MAX);
;
; cc65 fastcall:
;
;   stacked: host, path, leaf, output
;   AX:      capacity
; ---------------------------------------------------------------------------

        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     pushax

        jsr     load_browse_path_ax
        jsr     pushax

        lda     #<empty_string
        ldx     #>empty_string
        jsr     pushax

        lda     #<_uri_buf
        ldx     #>_uri_buf
        jsr     pushax

        lda     #<BBC_URI_WORK_MAX
        ldx     #>BBC_URI_WORK_MAX
        jsr     _config_nio_compose_uri

        cmp     #0
        jeq     return0


; ---------------------------------------------------------------------------
; fetch_start = browse_start
; browse_more = 0
; browse_next = browse_start
; ---------------------------------------------------------------------------

        lda     _browse_start
        sta     fetch_start
        sta     _browse_next

        lda     _browse_start+1
        sta     fetch_start+1
        sta     _browse_next+1

        lda     #0
        sta     _browse_more


; ===========================================================================
; Fetch enough protocol pages to fill the visible BBC page
; ===========================================================================

fetch_loop:
        ; remaining = BBC_BROWSE_PAGE_ROWS - state->entry_count
        jsr     restore_saved_state_ptr

        ldy     #STATE_ENTRY_COUNT
        lda     #BBC_BROWSE_PAGE_ROWS
        sec
        sbc     (ptr1),y
        sta     remaining

        ; Directory responses share storage with the slot-page cache.
        jsr     _config_nio_bbc_invalidate_slot_cache


; ---------------------------------------------------------------------------
; fnsvc_config_nio_list_directory_page(
;     state,
;     uri_buf,
;     fetch_start,
;     remaining,
;     &next_start,
;     &more);
;
; cc65 fastcall:
;
;   stacked: state
;            uri
;            start
;            max_entries
;            next_start
;
;   AX:      more
; ---------------------------------------------------------------------------

        jsr     load_state
        jsr     pushax

        lda     #<_uri_buf
        ldx     #>_uri_buf
        jsr     pushax

        lda     fetch_start
        ldx     fetch_start+1
        jsr     pushax

        lda     remaining
        jsr     pusha

        lda     #<next_start
        ldx     #>next_start
        jsr     pushax

        lda     #<more
        ldx     #>more
        jsr     _fnsvc_config_nio_list_directory_page

        cmp     #0
        jeq     return0


; ---------------------------------------------------------------------------
; browse_next = next_start
; browse_more = more
; ---------------------------------------------------------------------------

        lda     next_start
        sta     _browse_next

        lda     next_start+1
        sta     _browse_next+1

        lda     more
        sta     _browse_more

        ; if (!more)
        beq     fetch_complete


; ---------------------------------------------------------------------------
; Stop if the service did not advance:
;
;   next_start == fetch_start
; ---------------------------------------------------------------------------

        lda     next_start
        cmp     fetch_start
        bne     fetch_advanced

        lda     next_start+1
        cmp     fetch_start+1
        beq     fetch_complete


fetch_advanced:
        ; fetch_start = next_start
        lda     next_start
        sta     fetch_start

        lda     next_start+1
        sta     fetch_start+1

        ; Continue while state->entry_count < BBC_BROWSE_PAGE_ROWS.
        jsr     restore_saved_state_ptr

        ldy     #STATE_ENTRY_COUNT
        lda     (ptr1),y
        cmp     #BBC_BROWSE_PAGE_ROWS
        bcc     fetch_loop


; ===========================================================================
; Successful completion
; ===========================================================================

fetch_complete:
        lda     #0
        sta     _selected_entry

        jmp     return1


; Return &state->browse_path in AX.
load_browse_path_ax:
        jsr     load_state
        clc
        adc     #STATE_BROWSE_PATH
        sta     browse_path_low

        txa
        adc     #0
        tax

        lda     browse_path_low
        rts

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

_handle_browse:
        sta     browse_saved_key

        ; Cursor codes must be tested before ASCII case folding.
        lda     browse_saved_key

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
        lda     browse_saved_key
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

        sta     browse_old_selection
        dec     _selected_entry

        lda     browse_old_selection
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
        jsr     restore_saved_state_ptr

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
        sta     browse_old_selection
        inc     _selected_entry

        lda     browse_old_selection
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
        jsr     load_state
        jsr     _fetch_next_browse_page

        ; Return the helper's Boolean result directly after removing state.
        jmp     incsp2


browse_previous:
        lda     _browse_start
        ora     _browse_start+1
        jeq     return_false

call_previous_page:
        jsr     load_state
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
        jsr     load_state
        jsr     _fetch_browse_page

        jmp     return_true


; ===========================================================================
; Assign currently selected file
; ===========================================================================

browse_assign:
        jsr     load_state
        jsr     _assign_selected_file

        ; assign_selected_file() returns void; the UI always redraws.
        jmp     return_true


; ===========================================================================
; Return/newline action
; ===========================================================================

browse_enter:
        ; Nothing can be selected when entry_count is zero.
        jsr     restore_saved_state_ptr
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

        lda     #<(entry_tmp+ENTRY_NAME)
        ldx     #>(entry_tmp+ENTRY_NAME)
        jsr     _config_nio_bbc_enter_dir

        ; A failed enter still causes the screen to redraw in the C version.
        cmp     #0
        jeq     return_true

        ; Successful directory change starts pagination again from zero.
        lda     #0
        sta     _browse_start
        sta     _browse_start+1
        sta     _browse_page_depth

        jsr     load_state
        jsr     _fetch_browse_page

        jmp     return_true


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
        stx     browse_marker_char

        clc
        adc     #CONFIG_NIO_BBC_BROWSE_ROWS_Y
        pha                             ; calculated y

        lda     #CONFIG_NIO_BBC_BROWSE_ROWS_X
        jsr     pusha                   ; stacked x argument

        pla                             ; fastcall y argument
        jsr     _gotoxy

        lda     browse_marker_char
        jmp     _cputc


; int prompt_assign_slot(config_nio_state_t *state, uint8_t *slot_out)
;
; BBC slot-selection dialogue. slot_out is the fastcall argument in A/X and
; state is removed from the C argument stack at entry.

_prompt_assign_slot:
        sta     slot_out_ptr
        stx     slot_out_ptr+1
        jsr     popax
        sta     assign_state_ptr
        stx     assign_state_ptr+1

        lda     slot_out_ptr
        ora     slot_out_ptr+1
        bne     have_output
        jmp     return0

have_output:
        jsr     restore_assign_state_ptr
        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        sta     saved_slot_start

        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_Y
        sta     clear_row
clear_dialog_loop:
        ldx     #CONFIG_NIO_BBC_BROWSE_ASSIGN_X
        lda     clear_row
        jsr     goto_xy
        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_CLEAR_WIDTH
        jsr     write_spaces
        inc     clear_row
        lda     clear_row
        cmp     #(CONFIG_NIO_BBC_BROWSE_ASSIGN_Y+CONFIG_NIO_BBC_BROWSE_ASSIGN_CLEAR_ROWS)
        bne     clear_dialog_loop

        ldx     #CONFIG_NIO_BBC_BROWSE_ASSIGN_X
        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_TITLE_Y
        jsr     goto_xy
        lda     #<assign_title
        ldx     #>assign_title
        jsr     _cputs
        ldx     #CONFIG_NIO_BBC_BROWSE_ASSIGN_X
        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_HINT_Y
        jsr     goto_xy
        lda     #<assign_hint
        ldx     #>assign_hint
        jsr     _cputs

        lda     _selected_slot
        sta     prompt_slot
        jsr     draw_assign_slots

key_loop:
        jsr     _cgetc
        sta     key_value
        cmp     #CH_ESC
        bne     check_enter
        jsr     restore_slot_start
        jsr     refresh_assign_slots
        jmp     return0

check_enter:
        cmp     #CH_EOL
        bne     check_lf
        jmp     choose_slot
check_lf:
        cmp     #$0A
        bne     check_digit
        jmp     choose_slot
check_digit:
        cmp     #'0'
        bcc     check_next_page
        cmp     #'8'
        bcs     check_next_page
        sec
        sbc     #'0'
        sta     prompt_slot
        sta     _selected_slot
        jmp     return_choice

check_next_page:
        lda     key_value
        jsr     _key_is_next_page
        cmp     #0
        beq     check_previous_page
        lda     _assign_slot_start
        cmp     #248
        bcc     advance_page
        jmp     key_loop
advance_page:
        clc
        adc     #FNCTL_MAX_UNITS
        sta     _assign_slot_start
        jsr     draw_assign_slots
        jmp     key_loop

check_previous_page:
        lda     key_value
        jsr     _key_is_previous_page
        cmp     #0
        beq     check_vertical
        lda     _assign_slot_start
        bne     retreat_page
        jmp     key_loop
retreat_page:
        sec
        sbc     #FNCTL_MAX_UNITS
        sta     _assign_slot_start
        jsr     draw_assign_slots
        jmp     key_loop

check_vertical:
        lda     prompt_slot
        sta     old_slot
        lda     key_value
        cmp     #CH_CURS_UP
        beq     move_up
        cmp     #'w'
        beq     move_up
        cmp     #'W'
        beq     move_up
        cmp     #CH_CURS_DOWN
        beq     move_down
        cmp     #'s'
        beq     move_down
        jmp     key_loop
move_down:
        lda     prompt_slot
        cmp     #(FNCTL_MAX_UNITS-1)
        bcc     do_move_down
        jmp     key_loop
do_move_down:
        inc     prompt_slot
        bne     update_markers
move_up:
        lda     prompt_slot
        bne     do_move_up
        jmp     key_loop
do_move_up:
        dec     prompt_slot

update_markers:
        lda     old_slot
        ldx     #' '
        jsr     set_assign_marker
        lda     prompt_slot
        ldx     #'>'
        jsr     set_assign_marker
        jmp     key_loop

choose_slot:
        lda     prompt_slot
        sta     _selected_slot
return_choice:
        clc
        lda     _assign_slot_start
        adc     _selected_slot
        pha
        lda     slot_out_ptr
        sta     ptr1
        lda     slot_out_ptr+1
        sta     ptr1+1
        pla
        ldy     #0
        sta     (ptr1),y
        jsr     restore_slot_start
        jmp     return1

; Refresh the eight cached records and render them. Unlike clear_field(), the
; row is positioned only once because the spaces leave the cursor at its start.
draw_assign_slots:
        jsr     restore_assign_state_ptr
        ldy     #STATE_SLOT_START
        lda     _assign_slot_start
        sta     (ptr1),y
        jsr     refresh_assign_slots

        lda     #0
        sta     assign_row_index
draw_assign_loop:
        ldx     #CONFIG_NIO_BBC_BROWSE_ASSIGN_X
        lda     assign_row_index
        clc
        adc     #CONFIG_NIO_BBC_BROWSE_ASSIGN_ROWS_Y
        jsr     goto_xy
        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_CLEAR_WIDTH
        jsr     write_spaces

        ldx     #CONFIG_NIO_BBC_BROWSE_ASSIGN_X
        lda     assign_row_index
        clc
        adc     #CONFIG_NIO_BBC_BROWSE_ASSIGN_ROWS_Y
        jsr     goto_xy
        lda     assign_row_index
        cmp     prompt_slot
        bne     assign_not_selected
        lda     #'>'
        bne     write_assign_marker
assign_not_selected:
        lda     #' '
write_assign_marker:
        jsr     OSWRCH
        lda     #' '
        jsr     OSWRCH
        lda     _assign_slot_start
        clc
        adc     assign_row_index
        jsr     _put_slot_index
        lda     #' '
        jsr     OSWRCH

        lda     assign_row_index
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_bbc_slot_get
        cmp     #0
        beq     empty_assign_slot
        lda     #<(_config_nio_store_buf+SLOT_URI)
        ldx     #>(_config_nio_store_buf+SLOT_URI)
        jsr     pushax
        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_URI_WIDTH
        jsr     _config_nio_bbc_put_tail
        jmp     next_assign_row
empty_assign_slot:
        lda     #0
        tax
        jsr     pushax
        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_URI_WIDTH
        jsr     _config_nio_bbc_put_fixed
next_assign_row:
        inc     assign_row_index
        lda     assign_row_index
        cmp     #FNCTL_MAX_UNITS
        bne     draw_assign_loop
        rts

; A = row within the selection page, X = marker character.
set_assign_marker:
        stx     assign_marker_char
        clc
        adc     #CONFIG_NIO_BBC_BROWSE_ASSIGN_ROWS_Y
        pha
        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_X
        jsr     pusha
        pla
        jsr     _gotoxy
        lda     assign_marker_char
        jmp     OSWRCH

refresh_assign_slots:
        lda     assign_state_ptr
        ldx     assign_state_ptr+1
        jmp     _config_nio_refresh_slots

restore_slot_start:
        jsr     restore_assign_state_ptr
        ldy     #STATE_SLOT_START
        lda     saved_slot_start
        sta     (ptr1),y
        rts

restore_assign_state_ptr:
        lda     assign_state_ptr
        sta     ptr1
        lda     assign_state_ptr+1
        sta     ptr1+1
        rts
