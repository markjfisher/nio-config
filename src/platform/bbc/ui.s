.export  _mode7
.export  _draw_slots

.import  _config_nio_bbc_cursor
.import  _config_nio_bbc_load_template
.import  _draw_drive_rows
.import  _draw_slot_rows
.import  load_state

.import  _cputc

.import  incsp2
.import  pushax

; TODO: need to check MASTER and use MODE 7+128, to use shadow RAM
_mode7:
        lda     #22             ; VDU 22,7 == mode 7
        jsr     _cputc
        lda     #7
        jsr     _cputc
        lda     #$00
        jmp     _config_nio_bbc_cursor

; void draw_slots(config_nio_state_t *state)
_draw_slots:
        jsr     pushax                  ; save state on stack for load_state

        lda     #<slots_file
        ldx     #>slots_file
        jsr     _config_nio_bbc_load_template

        jsr     load_state
        jsr     _draw_slot_rows

        jsr     load_state
        jsr     _draw_drive_rows

        jmp     incsp2                  ; reset stack

.data
slots_file:     .byte "CNSLOTS", 0
