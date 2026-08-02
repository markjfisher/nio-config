; Browse-page navigation for the BBC UI.

        .export _fetch_next_browse_page
        .export _fetch_previous_browse_page

        .import _fetch_browse_page
        .import _browse_more
        .import _browse_start
        .import _browse_next
        .import _browse_page_stack
        .import _browse_page_depth
        .import _selected_entry
        .import return0, return1
        .importzp ptr1

STATE_ENTRY_COUNT    = 5
BBC_BROWSE_PAGE_STACK = 6

        .code

; int fetch_next_browse_page(config_nio_state_t *state)
_fetch_next_browse_page:
        sta     saved_state
        stx     saved_state+1

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
        sta     saved_state
        stx     saved_state+1

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
        jsr     restore_state_ptr
        ldy     #STATE_ENTRY_COUNT
        lda     (ptr1),y
        beq     previous_done
        sec
        sbc     #1
        sta     _selected_entry
previous_done:
        ; The C API deliberately reports redraw even when the fetch failed.
        jmp     return1

load_state:
        lda     saved_state
        ldx     saved_state+1
        rts

restore_state_ptr:
        lda     saved_state
        sta     ptr1
        lda     saved_state+1
        sta     ptr1+1
        rts

        .bss
saved_state: .res 2
old_start:   .res 2
