; ===========================================================================
; uint8_t handle_slots(config_nio_state_t *state, int key)
;
; cc65 fastcall entry:
;
;   A       = key low byte
;   X       = key high byte, ignored because key originates from cgetc()
;   c_sp+0  = state low
;   c_sp+1  = state high
;
; The stacked state argument is removed through incsp2 on every return.
;
; BBC-specific constants:
;
;   FNCTL_MAX_UNITS = 8
;   BBC_DRIVE_COUNT = 4
;
; config_nio_set_status() is a no-op for the external BBC state model.
; ===========================================================================

.macpack longbranch

.export _handle_slots

.importzp c_sp
.importzp ptr1

.import pusha
.import pushax
.import incsp2

.import _gotoxy
.import _cputc

.import _config_nio_refresh_slots
.import _draw_slot_rows
.import _config_nio_bbc_mapping_get
.import _config_nio_bbc_mapping_set
.import _config_nio_bbc_mapping_clear
.import _config_nio_save_mappings
.import _config_nio_delete_slot

.import _selected_drive
.import _selected_slot
.import _slots_focus


.include "config_nio_layout.inc"
.include "bbc_keycodes.inc"

; ---------------------------------------------------------------------------
; config_nio_state_t offsets, external BBC state model
; ---------------------------------------------------------------------------

STATE_SLOT_START  = 1
STATE_SLOTS_MORE  = 3


; ---------------------------------------------------------------------------
; config_nio_mapping_t offsets
; ---------------------------------------------------------------------------

MAPPING_VALID     = 0
MAPPING_SLOT      = 1
MAPPING_READONLY  = 2
MAPPING_SIZE      = 3


.segment "CODE"

_handle_slots:
        sta     saved_key

        ; Preserve state independently of the changing C software stack.
        ldy     #1
        lda     (c_sp),y
        sta     saved_state+1
        dey
        lda     (c_sp),y
        sta     saved_state

        ; Tab toggles between drive and slot focus.
        lda     saved_key
        cmp     #$09
        jeq     toggle_focus

        lda     _slots_focus
        jeq     drive_focus


; ===========================================================================
; Slot-list focus
; ===========================================================================

slot_focus:
        ; Test non-ASCII cursor codes before modifying the key.
        lda     saved_key

        cmp     #CH_CURS_RIGHT
        jeq     slot_next_page

        cmp     #CH_CURS_LEFT
        jeq     slot_previous_page

        cmp     #CH_CURS_UP
        jeq     slot_up

        cmp     #CH_CURS_DOWN
        jeq     slot_down

        ; Fold ASCII upper case into lower case.
        ora     #$20

        cmp     #'n'
        jeq     slot_next_page

        cmp     #'p'
        jeq     slot_previous_page

        cmp     #'w'
        jeq     slot_up

        cmp     #'s'
        jeq     slot_down

        ; ASCII digits already have bit 5 set, so ORA #$20 leaves them
        ; unchanged.
        sec
        sbc     #'0'
        bcc     slot_not_digit

        cmp     #4                      ; drives 0..3
        jcc     map_selected_slot

slot_not_digit:
        lda     saved_key
        ora     #$20

        cmp     #'c'
        jeq     clear_selected_slot

        ; On BBC this only causes a redraw; the status message itself is
        ; compiled away.
        cmp     #'e'
        jeq     return_true

        jmp     return_false


; ---------------------------------------------------------------------------
; Next slot page
; ---------------------------------------------------------------------------

slot_next_page:
        jsr     restore_state_ptr

        ldy     #STATE_SLOTS_MORE
        lda     (ptr1),y
        jeq     return_false

        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        clc
        adc     #8
        sta     (ptr1),y

        jsr     refresh_slots
        jsr     redraw_slot_rows
        jmp     return_false


; ---------------------------------------------------------------------------
; Previous slot page
; ---------------------------------------------------------------------------

slot_previous_page:
        jsr     restore_state_ptr

        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        jeq     return_false

        cmp     #8
        bcc     previous_page_zero

        ; Carry is already set by CMP because slot_start >= 8.
        sbc     #8
        bcs     store_previous_page     ; always

previous_page_zero:
        lda     #0

store_previous_page:
        sta     (ptr1),y

        jsr     refresh_slots
        jsr     redraw_slot_rows
        jmp     return_false


; ---------------------------------------------------------------------------
; Move selected slot up
; ---------------------------------------------------------------------------

redraw_slot_rows:
        jsr     load_state_ax
        jmp     _draw_slot_rows

slot_up:
        lda     _selected_slot
        jeq     return_false

        sta     old_selection
        dec     _selected_slot

        lda     old_selection
        ldx     #' '
        jsr     slot_marker

        lda     _selected_slot
        ldx     #'>'
        jsr     slot_marker

        jmp     return_false


; ---------------------------------------------------------------------------
; Move selected slot down
; ---------------------------------------------------------------------------

slot_down:
        lda     _selected_slot
        cmp     #7
        jcs     return_false

        sta     old_selection
        inc     _selected_slot

        lda     old_selection
        ldx     #' '
        jsr     slot_marker

        lda     _selected_slot
        ldx     #'>'
        jsr     slot_marker

        jmp     return_false


; ---------------------------------------------------------------------------
; Assign selected slot to drive 0..3
;
; Entry:
;   A = unit
; ---------------------------------------------------------------------------

map_selected_slot:
        sta     saved_unit

        lda     #1
        sta     mapping_tmp+MAPPING_VALID

        jsr     restore_state_ptr
        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        clc
        adc     _selected_slot
        sta     mapping_tmp+MAPPING_SLOT

        lda     #0
        sta     mapping_tmp+MAPPING_READONLY

        ; config_nio_bbc_mapping_set(unit, &mapping_tmp)
        lda     saved_unit
        jsr     pusha

        lda     #<mapping_tmp
        ldx     #>mapping_tmp
        jsr     _config_nio_bbc_mapping_set

        ; The C implementation ignores both results.
        jsr     save_mappings

        lda     saved_unit
        sta     _selected_drive

        jmp     return_true


; ---------------------------------------------------------------------------
; Delete the selected absolute slot and clear mappings referring to it
; ---------------------------------------------------------------------------

clear_selected_slot:
        jsr     restore_state_ptr

        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        clc
        adc     _selected_slot
        sta     absolute_slot

        ; config_nio_delete_slot(state, absolute_slot)
        jsr     load_state_ax
        jsr     pushax

        lda     absolute_slot
        jsr     _config_nio_delete_slot

        ; Delete failure still returns redraw=1 in the original function.
        cmp     #0
        jeq     return_true

        lda     #0
        sta     saved_unit

clear_mapping_loop:
        ; config_nio_bbc_mapping_get(unit, &mapping_tmp)
        lda     saved_unit
        jsr     pusha

        lda     #<mapping_tmp
        ldx     #>mapping_tmp
        jsr     _config_nio_bbc_mapping_get

        cmp     #0
        beq     next_mapping

        lda     mapping_tmp+MAPPING_VALID
        beq     next_mapping

        lda     mapping_tmp+MAPPING_SLOT
        cmp     absolute_slot
        bne     next_mapping

        lda     saved_unit
        jsr     _config_nio_bbc_mapping_clear

next_mapping:
        inc     saved_unit
        lda     saved_unit
        cmp     #8
        bne     clear_mapping_loop

        jsr     save_mappings
        jsr     refresh_slots

        jmp     return_true


; ===========================================================================
; Drive-list focus
; ===========================================================================

drive_focus:
        lda     saved_key

        cmp     #CH_CURS_UP
        jeq     drive_up

        cmp     #CH_CURS_DOWN
        jeq     drive_down

        ora     #$20

        cmp     #'w'
        jeq     drive_up

        cmp     #'s'
        jeq     drive_down

        cmp     #'r'
        jeq     toggle_readonly

        cmp     #'c'
        jeq     clear_drive_mapping

        jmp     return_false


; ---------------------------------------------------------------------------
; Move selected drive up
; ---------------------------------------------------------------------------

drive_up:
        lda     _selected_drive
        jeq     return_false

        sta     old_selection
        dec     _selected_drive

        lda     old_selection
        ldx     #' '
        jsr     drive_marker

        lda     _selected_drive
        ldx     #'>'
        jsr     drive_marker

        jmp     return_false


; ---------------------------------------------------------------------------
; Move selected drive down
; ---------------------------------------------------------------------------

drive_down:
        lda     _selected_drive
        cmp     #3
        jcs     return_false

        sta     old_selection
        inc     _selected_drive

        lda     old_selection
        ldx     #' '
        jsr     drive_marker

        lda     _selected_drive
        ldx     #'>'
        jsr     drive_marker

        jmp     return_false


; ---------------------------------------------------------------------------
; Toggle read-only state of selected drive mapping
; ---------------------------------------------------------------------------

toggle_readonly:
        ; config_nio_bbc_mapping_get(selected_drive, &mapping_tmp)
        lda     _selected_drive
        jsr     pusha

        lda     #<mapping_tmp
        ldx     #>mapping_tmp
        jsr     _config_nio_bbc_mapping_get

        cmp     #0
        beq     readonly_done

        lda     mapping_tmp+MAPPING_VALID
        beq     readonly_done

        lda     mapping_tmp+MAPPING_READONLY
        eor     #1
        sta     mapping_tmp+MAPPING_READONLY

        ; config_nio_bbc_mapping_set(selected_drive, &mapping_tmp)
        lda     _selected_drive
        jsr     pusha

        lda     #<mapping_tmp
        ldx     #>mapping_tmp
        jsr     _config_nio_bbc_mapping_set

        jsr     save_mappings

readonly_done:
        ; The C function returns 1 even if there was no valid mapping.
        jmp     return_true


; ---------------------------------------------------------------------------
; Clear selected drive mapping
; ---------------------------------------------------------------------------

clear_drive_mapping:
        lda     _selected_drive
        jsr     _config_nio_bbc_mapping_clear

        jsr     save_mappings
        jmp     return_true


; ===========================================================================
; Toggle focus
; ===========================================================================

toggle_focus:
        lda     _slots_focus
        jeq     focus_was_drives


; ---------------------------------------------------------------------------
; Current focus is slots:
;
;   remove slot marker
;   switch focus to drives
;   add drive marker
; ---------------------------------------------------------------------------

focus_was_slots:
        lda     _selected_slot
        ldx     #' '
        jsr     slot_marker

        lda     #0
        sta     _slots_focus

        lda     _selected_drive
        ldx     #'>'
        jsr     drive_marker

        jmp     return_false


; ---------------------------------------------------------------------------
; Current focus is drives:
;
;   remove drive marker
;   switch focus to slots
;   add slot marker
; ---------------------------------------------------------------------------

focus_was_drives:
        lda     _selected_drive
        ldx     #' '
        jsr     drive_marker

        lda     #1
        sta     _slots_focus

        lda     _selected_slot
        ldx     #'>'
        jsr     slot_marker

        jmp     return_false


; ===========================================================================
; Shared state helpers
; ===========================================================================

; Restore the persistent state pointer into zero-page ptr1.
restore_state_ptr:
        lda     saved_state
        sta     ptr1
        lda     saved_state+1
        sta     ptr1+1
        rts


; Load state directly into AX.
load_state_ax:
        lda     saved_state
        ldx     saved_state+1
        rts


; config_nio_refresh_slots(state)
refresh_slots:
        jsr     load_state_ax
        jmp     _config_nio_refresh_slots


; config_nio_save_mappings(state)
save_mappings:
        jsr     load_state_ax
        jmp     _config_nio_save_mappings


; ===========================================================================
; Marker helpers
;
; Entry:
;
;   A = row
;   X = marker character, normally '>' or ' '
;
; cc65 gotoxy signature:
;
;   void gotoxy(unsigned char x, unsigned char y)
;
; x is pushed onto the C software stack; y is passed in A.
; ===========================================================================

slot_marker:
        stx     marker_char

        clc
        adc     #CONFIG_NIO_BBC_SLOTS_SLOTS_Y
        pha                             ; preserve calculated y

        lda     #CONFIG_NIO_BBC_SLOTS_SLOTS_X
        jsr     pusha                   ; stacked x argument

        pla                             ; fastcall y argument
        jsr     _gotoxy

        lda     marker_char
        jmp     _cputc


drive_marker:
        stx     marker_char

        clc
        adc     #CONFIG_NIO_BBC_SLOTS_DRIVES_Y
        pha                             ; preserve calculated y

        lda     #CONFIG_NIO_BBC_SLOTS_DRIVES_X
        jsr     pusha                   ; stacked x argument

        pla                             ; fastcall y argument
        jsr     _gotoxy

        lda     marker_char
        jmp     _cputc


; ===========================================================================
; Shared return paths
;
; incsp2 removes the original stacked state pointer. For a uint8_t result,
; the return value is in A.
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

mapping_tmp:
        .res    MAPPING_SIZE

saved_key:
        .res    1

saved_unit:
        .res    1

absolute_slot:
        .res    1

old_selection:
        .res    1

marker_char:
        .res    1
