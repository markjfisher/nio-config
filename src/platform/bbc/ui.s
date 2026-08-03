.export  _mode7
.export  _draw_slots
.export  load_state
.export  restore_saved_state_ptr

.import  _config_nio_bbc_cursor
.import  _config_nio_bbc_load_template
.import  _draw_drive_rows
.import  _draw_slot_rows
.import  _saved_state

.importzp ptr1

.import  _cputc

; TODO: need to check MASTER and use MODE 7+128, to use shadow RAM
_mode7:
        lda     #22             ; VDU 22,7 == mode 7
        jsr     _cputc
        lda     #7
        jsr     _cputc
        lda     #$00
        jmp     _config_nio_bbc_cursor

; Return the shared config_nio_state_t pointer in AX.
load_state:
        lda     _saved_state
        ldx     _saved_state+1
        rts

; Restore the shared state pointer into zero-page ptr1.
restore_saved_state_ptr:
        jsr     load_state
        sta     ptr1
        stx     ptr1+1
        rts

; void draw_slots(config_nio_state_t *state)
_draw_slots:
        lda     #<slots_file
        ldx     #>slots_file
        jsr     _config_nio_bbc_load_template

        jsr     load_state
        jsr     _draw_slot_rows

        jsr     load_state
        jmp     _draw_drive_rows

.data
slots_file:     .byte "CNSLOTS", 0
