; int prompt_assign_slot(config_nio_state_t *state, uint8_t *slot_out)
;
; BBC slot-selection dialogue. slot_out is the fastcall argument in A/X and
; state is removed from the C argument stack at entry.

        .export _prompt_assign_slot

        .import OSWRCH
        .import _cgetc, _cputs, _gotoxy
        .import _config_nio_bbc_put_fixed
        .import _config_nio_bbc_put_tail
        .import _config_nio_bbc_slot_get
        .import _config_nio_refresh_slots
        .import _config_nio_store_buf
        .import _key_is_next_page
        .import _key_is_previous_page
        .import _put_slot_index
        .import _assign_slot_start
        .import _selected_slot
        .import popax, pusha, pushax, return0, return1
        .importzp ptr1

        .include "config_nio_layout.inc"
        .include "constants.inc"

STATE_SLOT_START = 1
SLOT_URI         = 1
FNCTL_MAX_UNITS  = 8

        .code

_prompt_assign_slot:
        sta     slot_out_ptr
        stx     slot_out_ptr+1
        jsr     popax
        sta     state_ptr
        stx     state_ptr+1

        lda     slot_out_ptr
        ora     slot_out_ptr+1
        bne     have_output
        jmp     return0

have_output:
        jsr     restore_state_ptr
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
        jsr     refresh_slots
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
        jsr     restore_state_ptr
        ldy     #STATE_SLOT_START
        lda     _assign_slot_start
        sta     (ptr1),y
        jsr     refresh_slots

        lda     #0
        sta     row_index
draw_assign_loop:
        ldx     #CONFIG_NIO_BBC_BROWSE_ASSIGN_X
        lda     row_index
        clc
        adc     #CONFIG_NIO_BBC_BROWSE_ASSIGN_ROWS_Y
        jsr     goto_xy
        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_CLEAR_WIDTH
        jsr     write_spaces

        ldx     #CONFIG_NIO_BBC_BROWSE_ASSIGN_X
        lda     row_index
        clc
        adc     #CONFIG_NIO_BBC_BROWSE_ASSIGN_ROWS_Y
        jsr     goto_xy
        lda     row_index
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
        adc     row_index
        jsr     _put_slot_index
        lda     #' '
        jsr     OSWRCH

        lda     row_index
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
        inc     row_index
        lda     row_index
        cmp     #FNCTL_MAX_UNITS
        bne     draw_assign_loop
        rts

; A = row within the selection page, X = marker character.
set_assign_marker:
        stx     marker_char
        clc
        adc     #CONFIG_NIO_BBC_BROWSE_ASSIGN_ROWS_Y
        pha
        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_X
        jsr     pusha
        pla
        jsr     _gotoxy
        lda     marker_char
        jmp     OSWRCH

refresh_slots:
        lda     state_ptr
        ldx     state_ptr+1
        jmp     _config_nio_refresh_slots

restore_slot_start:
        jsr     restore_state_ptr
        ldy     #STATE_SLOT_START
        lda     saved_slot_start
        sta     (ptr1),y
        rts

restore_state_ptr:
        lda     state_ptr
        sta     ptr1
        lda     state_ptr+1
        sta     ptr1+1
        rts

; X = column, A = row.
goto_xy:
        pha
        txa
        jsr     pusha
        pla
        jmp     _gotoxy

; Write A spaces. OSWRCH preserves X on the BBC MOS interface.
write_spaces:
        tax
        lda     #' '
write_space_loop:
        jsr     OSWRCH
        dex
        bne     write_space_loop
        rts

        .rodata
assign_title:
        .byte   "Assign file to slot", 0
assign_hint:
        .byte   "P/N page  RET choose  ESC cancel", 0

        .bss
state_ptr:        .res 2
slot_out_ptr:     .res 2
prompt_slot:      .res 1
saved_slot_start: .res 1
clear_row:        .res 1
row_index:        .res 1
key_value:        .res 1
old_slot:         .res 1
marker_char:      .res 1
