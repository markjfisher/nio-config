; ===========================================================================
; int fetch_browse_page(config_nio_state_t *state)
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

.macpack longbranch

.export _fetch_browse_page

.importzp ptr1

.import pusha
.import pushax

.import _config_nio_bbc_host_get
.import _config_nio_compose_uri
.import _config_nio_bbc_invalidate_slot_cache
.import _fnsvc_config_nio_list_directory_page

.import _config_nio_store_buf
.import _uri_buf

.import _browse_host
.import _browse_start
.import _browse_next
.import _browse_more
.import _selected_entry

.include "config_nio_layout.inc"
.include "constants.inc"

; ---------------------------------------------------------------------------
; External BBC config_nio_state_t offsets
; ---------------------------------------------------------------------------

STATE_ENTRY_COUNT       = 5
STATE_ENTRIES_TRUNCATED = 8
STATE_BROWSE_PATH       = 9


; ---------------------------------------------------------------------------
; BBC-specific sizes
; ---------------------------------------------------------------------------

; This should already be provided by the generated/layout include used by the
; BBC assembly build. Defining the alias here mirrors the C source.
BBC_BROWSE_PAGE_ROWS    = CONFIG_NIO_BBC_BROWSE_ROWS_COUNT


.segment "CODE"

_fetch_browse_page:
        sta     saved_state
        stx     saved_state+1

        ; state->entry_count = 0
        ; state->entries_truncated = 0
        jsr     restore_state_ptr

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
        jsr     restore_state_ptr

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

        jsr     load_state_ax
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
        jsr     restore_state_ptr

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

        lda     #1
        ldx     #0
        rts


return0:
        lda     #0
        tax
        rts


; ===========================================================================
; State-pointer helpers
; ===========================================================================

restore_state_ptr:
        lda     saved_state
        sta     ptr1

        lda     saved_state+1
        sta     ptr1+1
        rts


load_state_ax:
        lda     saved_state
        ldx     saved_state+1
        rts


; Return &state->browse_path in AX.
load_browse_path_ax:
        lda     saved_state
        clc
        adc     #STATE_BROWSE_PATH
        sta     browse_path_low

        lda     saved_state+1
        adc     #0
        tax

        lda     browse_path_low
        rts


.segment "RODATA"

empty_string:
        .byte   0


; ===========================================================================
; Non-reentrant scratch storage
; ===========================================================================

.segment "BSS"

saved_state:
        .res    2

fetch_start:
        .res    2

next_start:
        .res    2

more:
        .res    1

remaining:
        .res    1

browse_path_low:
        .res    1