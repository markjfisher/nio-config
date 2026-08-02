; Host-list drawing, editing, and removal for the BBC UI.

        .export _show_hosts
        .export _edit_host
        .export _clear_host

        .import OSWRCH
        .import _gotoxy
        .import _config_nio_bbc_host_get
        .import _config_nio_bbc_host_set
        .import _config_nio_bbc_host_clear
        .import _config_nio_bbc_load_template
        .import _config_nio_bbc_put_fixed
        .import _config_nio_bbc_put_tail
        .import _config_nio_save_hosts
        .import _config_nio_store_buf
        .import _prompt_host
        .import _selected_host
        .import _hosts_start
        .import pusha, pushax
        .importzp ptr1

        .include "config_nio_layout.inc"
        .include "config_nio_host_table.inc"

STATE_HOST_COUNT = 0
HOST_MAX = CONFIG_NIO_BBC_HOST_MAX
BBC_EDIT_BUF_SIZE = CONFIG_NIO_BBC_HOST_SIZE
BBC_HOST_ROW_WIDTH = CONFIG_NIO_BBC_HOSTS_ROWS_URI_WIDTH + 4

        .code

; void show_hosts(config_nio_state_t *state)
_show_hosts:
        sta     saved_state
        stx     saved_state+1

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
        jsr     restore_state_ptr
        ldy     #STATE_HOST_COUNT
        lda     (ptr1),y
        sta     display_host_count

        lda     #<hosts_template
        ldx     #>hosts_template
        jsr     _config_nio_bbc_load_template
        lda     #0
        sta     row_index

host_row_loop:
        ldx     #CONFIG_NIO_BBC_HOSTS_ROWS_X
        lda     row_index
        clc
        adc     #CONFIG_NIO_BBC_HOSTS_ROWS_Y
        jsr     goto_xy

        lda     _hosts_start
        clc
        adc     row_index
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
        inc     row_index
        lda     row_index
        cmp     #CONFIG_NIO_BBC_HOSTS_ROWS_COUNT
        beq     hosts_drawn
        jmp     host_row_loop
hosts_drawn:
        rts

; void edit_host(config_nio_state_t *state)
_edit_host:
        sta     saved_state
        stx     saved_state+1
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
        jsr     restore_state_ptr
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

        jsr     restore_state_ptr
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
        sta     saved_state
        stx     saved_state+1
        jsr     restore_state_ptr
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
        jsr     restore_state_ptr
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

; X = column, A = row.
goto_xy:
        pha
        txa
        jsr     pusha
        pla
        jmp     _gotoxy

        .rodata
hosts_template:
        .byte   "CNHOSTS", 0

        .bss
saved_state:        .res 2
display_host_count: .res 1
action_host_count:  .res 1
row_index:          .res 1
host_index:         .res 1
call_high:          .res 1
