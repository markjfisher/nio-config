        .export _config_nio_bbc_edit_buf
        .export _config_nio_bbc_edit_cap
        .export _config_nio_bbc_edit_x
        .export _config_nio_bbc_edit_y
        .export _config_nio_bbc_edit_width
        .export _config_nio_bbc_edit_line

        .import _cgetc
        .import _cursor
        .import _config_nio_bbc_cursor
        .importzp ptr1

        .include "oslib/os.inc"

CH_ESC          = $1B
CH_EOL          = $0D
CH_CURS_LEFT    = $88
CH_CURS_RIGHT   = $89
CH_DEL          = $7F
        .bss
_config_nio_bbc_edit_buf:
        .res    2
_config_nio_bbc_edit_cap:
        .res    1
_config_nio_bbc_edit_x:
        .res    1
_config_nio_bbc_edit_y:
        .res    1
_config_nio_bbc_edit_width:
        .res    1
edit_len:
        .res    1
edit_pos:
        .res    1
edit_max:
        .res    1
edit_start:
        .res    1
edit_key:
        .res    1
edit_ch:
        .res    1
edit_dst:
        .res    1
edit_col:
        .res    1
edit_src:
        .res    1
edit_cursor_x:
        .res    1

        .code

; int config_nio_bbc_edit_line(void)
_config_nio_bbc_edit_line:
        jsr     load_buf_ptr
        lda     ptr1
        ora     ptr1+1
        beq     @bad
        lda     _config_nio_bbc_edit_cap
        beq     @bad
        sec
        sbc     #1
        sta     edit_max
        jmp     @init_ok
@bad:
        jmp     return0

@init_ok:
        ldy     #0
@len_loop:
        cpy     edit_max
        beq     @len_done
        lda     (ptr1),y
        beq     @len_done
        iny
        bne     @len_loop
@len_done:
        sty     edit_len
        sty     edit_pos
        lda     #0
        sta     (ptr1),y
        jsr     cursor_off
        jsr     draw_field

edit_read:
        jsr     cursor_on
        jsr     _cgetc
        sta     edit_key                ; low byte is the useful key code
        jsr     cursor_off
        jsr     load_buf_ptr
        lda     edit_key
        cmp     #CH_ESC
        beq     return0
        cmp     #CH_EOL
        beq     return1
        cmp     #$0A
        beq     return1
        cmp     #CH_CURS_LEFT
        beq     do_key_left
        cmp     #$01                    ; Ctrl-A
        beq     do_key_home
        cmp     #CH_CURS_RIGHT
        beq     do_key_right
        cmp     #$05                    ; Ctrl-E
        beq     do_key_end
        cmp     #$0B                    ; Ctrl-K
        beq     do_key_kill
        cmp     #CH_DEL
        beq     do_key_backspace
        cmp     #$04                    ; Ctrl-D/delete under cursor
        beq     do_key_delete
        cmp     #$20
        bcc     edit_redraw
        cmp     #$7F
        bcs     edit_redraw
        jsr     key_insert
edit_redraw:
        jsr     draw_field
        jmp     edit_read

do_key_home:
        jsr     key_home
        jmp     edit_redraw

do_key_end:
        jsr     key_end
        jmp     edit_redraw

do_key_left:
        jsr     key_left
        jmp     edit_redraw

do_key_right:
        jsr     key_right
        jmp     edit_redraw

do_key_kill:
        jsr     key_kill
        jmp     edit_redraw

do_key_backspace:
        jsr     key_backspace
        jmp     edit_redraw

do_key_delete:
        jsr     key_delete
        jmp     edit_redraw

return0:
        jsr     cursor_off
        lda     #0
        tax
        rts

return1:
        jsr     cursor_off
        lda     #1
        ldx     #0
        rts

key_home:
        lda     #0
        sta     edit_pos
        rts

key_end:
        lda     edit_len
        sta     edit_pos
        rts

key_left:
        lda     edit_pos
        beq     @done
        dec     edit_pos
@done: rts

key_right:
        lda     edit_pos
        cmp     edit_len
        bcs     @done
        inc     edit_pos
@done: rts

key_kill:
        ldy     edit_pos
        sty     edit_len
        lda     #0
        sta     (ptr1),y
        rts

key_backspace:
        lda     edit_pos
        beq     @done
        dec     edit_pos
        jmp     delete_at_pos
@done: rts

key_delete:
        lda     edit_pos
        cmp     edit_len
        bcs     @done
        jmp     delete_at_pos
@done: rts

delete_at_pos:
        lda     edit_pos
        sta     edit_dst
@loop:
        lda     edit_dst
        clc
        adc     #1
        tay                             ; source index
        jsr     load_buf_ptr
        lda     (ptr1),y
        pha
        ldy     edit_dst
        pla
        sta     (ptr1),y
        cmp     #0
        beq     @done
        inc     edit_dst
        jmp     @loop
@done:
        dec     edit_len
        rts

key_insert:
        sta     edit_ch
        jsr     load_buf_ptr
        lda     edit_len
        cmp     edit_max
        bcc     @insert_room
        lda     edit_pos
        cmp     edit_len
        bcs     @done
        ldy     edit_pos
        lda     edit_ch
        sta     (ptr1),y
        inc     edit_pos
        rts

@insert_room:
        ldy     edit_len
@shift:
        lda     (ptr1),y
        iny
        sta     (ptr1),y
        dey
        cpy     edit_pos
        beq     @place
        dey
        jmp     @shift
@place:
        ldy     edit_pos
        lda     edit_ch
        sta     (ptr1),y
        inc     edit_len
        inc     edit_pos
@done:
        rts

draw_field:
        jsr     load_buf_ptr
        lda     edit_pos
        cmp     _config_nio_bbc_edit_width
        bcs     @scroll
        lda     #0
        beq     @start_set
@scroll:
        sec
        sbc     _config_nio_bbc_edit_width
        clc
        adc     #1
@start_set:
        sta     edit_start

        lda     #31
        jsr     OSWRCH
        lda     _config_nio_bbc_edit_x
        jsr     OSWRCH
        lda     _config_nio_bbc_edit_y
        jsr     OSWRCH

        lda     #0
        sta     edit_col
        lda     edit_start
        sta     edit_src
@draw_loop:
        ldy     edit_src
        cpy     edit_len
        bcs     @space
        jsr     load_buf_ptr
        lda     (ptr1),y
        bne     @put
@space:
        lda     #' '
@put:
        jsr     OSWRCH
        inc     edit_src
        inc     edit_col
        lda     edit_col
        cmp     _config_nio_bbc_edit_width
        bcc     @draw_loop

        lda     edit_pos
        sec
        sbc     edit_start
        cmp     _config_nio_bbc_edit_width
        bcc     @cursor_col_ok
        lda     _config_nio_bbc_edit_width
        sec
        sbc     #1
@cursor_col_ok:
        clc
        adc     _config_nio_bbc_edit_x
        sta     edit_cursor_x
        lda     #31
        jsr     OSWRCH
        lda     edit_cursor_x
        jsr     OSWRCH
        lda     _config_nio_bbc_edit_y
        jmp     OSWRCH

cursor_on:
        lda     #1
        jsr     _cursor
        lda     #1
        jmp     _config_nio_bbc_cursor

cursor_off:
        lda     #0
        jsr     _cursor
        lda     #0
        jmp     _config_nio_bbc_cursor

load_buf_ptr:
        lda     _config_nio_bbc_edit_buf
        sta     ptr1
        lda     _config_nio_bbc_edit_buf+1
        sta     ptr1+1
        rts
