; Slots-page navigation for the BBC UI.

.export _config_nio_bbc_invalidate_slot_cache
.export _config_nio_mount_mappings
.export _config_nio_refresh_slots
.export _draw_drive_rows
.export _draw_slot_rows
.export _handle_slots
.export _put_slot_index
.export _refresh_runtime_mounts
.export _runtime_mount_display

.import _config_nio_appstore_buf
.import _config_nio_bbc_mapping_clear
.import _config_nio_bbc_mapping_get
.import _config_nio_bbc_mapping_set
.import _config_nio_bbc_put_basename
.import _config_nio_bbc_put_fixed
.import _config_nio_bbc_put_tail
.import _config_nio_bbc_slot_get
.import _config_nio_delete_slot
.import _config_nio_read_slot
.import _config_nio_read_slot_page
.import _config_nio_read_slot_page_previous
.import _config_nio_save_mappings
.import _config_nio_store_buf
.import _fn_bbc_device_call_raw
.import _fnsvc_bbc_resp_buf
.import _runtime_offsets
.import _selected_drive
.import _selected_slot
.import _slots_focus
.import _uri_buf
.import absolute_slot
.import active_start
.import active_valid
.import drive_index
.import goto_xy
.import load_state
.import mapping_tmp
.import mapping_slot
.import mapping_readonly
.import mount_cmd
.import mounted_count
.import mounts_device_status
.import mounts_loop_counter
.import mounts_request
.import mounts_response_len
.import OSCLI
.import OSWRCH
.import previous_start
.import previous_valid
.import requested_start
.import restore_saved_state_ptr
.import return_false
.import return_true
.import row_index
.import saved_unit
.import slot_marker_char
.import slot_row_index
.import slot_start
.import slots_old_selection
.import slots_saved_key
.import refresh_state_ptr
.import write_spaces

.ifdef CONFIG_NIO_BBC_XRAM_TABLES
.import _config_nio_bbc_slot_set
.else
.import _config_nio_bbc_slots
.endif

.importzp ptr1
.importzp tmp1
.importzp tmp2

.import _gotoxy
.import _cputc

.import incsp2
.import pusha
.import pushax
.import return0
.import return1

.macpack longbranch

.include "../config_nio_layout.inc"
.include "../bbc_keycodes.inc"

FNCTL_MAX_UNITS                 = 8

MAPPING_VALID                   = 0
MAPPING_SLOT                    = 1
MAPPING_READONLY                = 2
MAPPING_SIZE                    = 3

SLOT_ENABLED                    = 0
SLOT_URI                        = 1

PAGE_SIZE                       = 8
STATE_SLOT_START                = 1
STATE_SLOT_COUNT                = 2
STATE_SLOTS_MORE                = 3

BBC_DRIVE_COUNT                 = 4
BBC_RUNTIME_NAME_WIDTH          = 19

NIO_DEVICE_DISK                 = $FC
NIO_DISK_LIST_MOUNTS            = $0D
NIO_DISK_LIST_MOUNTS_HEADER     = 10
BBC_MOUNTS_PAYLOAD              = 240
NIO_DISK_LIST_MOUNTS_RESPONSE   = BBC_MOUNTS_PAYLOAD + NIO_DISK_LIST_MOUNTS_HEADER

LIST_VERSION                    = 0
LIST_FLAGS                      = 1
LIST_ENTRY_COUNT_LO             = 6
LIST_ENTRIES_LEN_LO             = 8
LIST_ENTRIES_LEN_HI             = 9
LIST_TEXT                       = NIO_DISK_LIST_MOUNTS_HEADER

.code

; BBC implementation of config_nio_mount_mappings().
;
; The external BBC state model stores mappings and slots through the table and
; slot-catalog services.  The app-store scratch buffer is reused for temporary
; records.  The writable command template needs only its three slot digits and
; drive digit changed for each mapping.

; int config_nio_mount_mappings(config_nio_state_t *state)
;   A/X = state pointer (fastcall)
_config_nio_mount_mappings:
        ; The state pointer is unused by the external model, but preserve the
        ; C function's null-pointer result.
        cpx     #0
        bne     state_ok
        cmp     #0
        bne     state_ok
        jmp     return0
state_ok:
        lda     #0
        sta     mounted_count
        lda     #'/'                    ; incremented to drive '0' below
        sta     mount_cmd+11

next_unit:
        inc     mount_cmd+11
        lda     mount_cmd+11
        cmp     #'0'+FNCTL_MAX_UNITS
        bne     unit_loop

        lda     mounted_count
        beq     no_mappings
        jmp     return1

no_mappings:
        jmp     return0

unit_loop:
        ; config_nio_bbc_mapping_get(unit, appstore scratch)
        and     #$0F                    ; ASCII drive digit to unit byte
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_bbc_mapping_get
        cmp     #0
        beq     next_unit

        lda     _config_nio_store_buf+MAPPING_VALID
        beq     next_unit

        lda     _config_nio_store_buf+MAPPING_SLOT
        sta     mount_cmd+7             ; preserve raw slot across read_slot

        ; config_nio_read_slot(slot, appstore scratch)
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_read_slot
        cmp     #0
        beq     next_unit
        lda     _config_nio_store_buf+SLOT_ENABLED
        beq     next_unit
        lda     _config_nio_store_buf+SLOT_URI
        beq     next_unit

        ; Build "FMOUNT hts u\r".  Slot indices are bytes, so repeated
        ; subtraction is smaller than decimal division helpers.  A retains
        ; the remainder while X advances through the ASCII digit values.
        lda     mount_cmd+7
        ldx     #'0'
hundreds_loop:
        cmp     #100
        bcc     hundreds_done
        sbc     #100
        inx
        bne     hundreds_loop
hundreds_done:
        stx     mount_cmd+7
        ldx     #'0'
tens_loop:
        cmp     #10
        bcc     tens_done
        sbc     #10
        inx
        bne     tens_loop
tens_done:
        stx     mount_cmd+8
        ora     #'0'
        sta     mount_cmd+9

        ldx     #<mount_cmd
        ldy     #>mount_cmd
        jsr     OSCLI
        inc     mounted_count
        jmp     next_unit

restore_refresh_state_ptr:
        lda     refresh_state_ptr
        sta     ptr1
        lda     refresh_state_ptr+1
        sta     ptr1+1
        rts

_config_nio_bbc_invalidate_slot_cache:
        lda     #0
        sta     active_valid
        sta     previous_valid
        rts

.ifdef CONFIG_NIO_BBC_XRAM_TABLES
get_slot_appbuf:
        jsr     pusha
        lda     #<_config_nio_appstore_buf
        ldx     #>_config_nio_appstore_buf
        jmp     _config_nio_bbc_slot_get

set_slot_appbuf:
        jsr     pusha
        lda     #<_config_nio_appstore_buf
        ldx     #>_config_nio_appstore_buf
        jmp     _config_nio_bbc_slot_set

get_slot_storebuf:
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jmp     _config_nio_bbc_slot_get

set_slot_storebuf:
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jmp     _config_nio_bbc_slot_set
.endif

swap_pages:
.ifdef CONFIG_NIO_BBC_XRAM_TABLES
        lda     #0
        sta     row_index
@loop:  lda     row_index
        jsr     get_slot_appbuf
        lda     row_index
        clc
        adc     #PAGE_SIZE
        jsr     get_slot_storebuf
        lda     row_index
        jsr     set_slot_storebuf
        lda     row_index
        clc
        adc     #PAGE_SIZE
        jsr     set_slot_appbuf
        inc     row_index
        lda     row_index
        cmp     #PAGE_SIZE
        bne     @loop
.else
        ldx     #0
@loop:  lda     _config_nio_bbc_slots,x
        tay
        lda     _fnsvc_bbc_resp_buf,x
        sta     _config_nio_bbc_slots,x
        tya
        sta     _fnsvc_bbc_resp_buf,x
        inx
        cpx     #PAGE_SIZE*30
        bne     @loop
.endif
        lda     active_start
        ldx     previous_start
        stx     active_start
        sta     previous_start
        rts

; int config_nio_refresh_slots(config_nio_state_t *state)
_config_nio_refresh_slots:
        sta     refresh_state_ptr
        stx     refresh_state_ptr+1
        ora     refresh_state_ptr+1
        bne     :+
        jmp     return0
:
        jsr     restore_refresh_state_ptr
        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        sta     requested_start
        lda     active_valid
        beq     @not_active
        lda     active_start
        cmp     requested_start
        beq     @count
@not_active:
        lda     previous_valid
        beq     @fetch
        lda     previous_start
        cmp     requested_start
        bne     @fetch
        jsr     swap_pages
        lda     #1
        sta     active_valid
        jmp     @count

@fetch:
        lda     active_valid
        beq     @read_active
        lda     requested_start
        sta     previous_start
        jsr     _config_nio_read_slot_page_previous
        cmp     #1
        bne     @previous_failed
        jsr     swap_pages
        lda     #1
        sta     previous_valid
        sta     active_valid
        jmp     @count

@read_active:
        lda     requested_start
        jsr     _config_nio_read_slot_page
        cmp     #1
        beq     @read_ok
        lda     #0
        sta     active_valid
        jmp     return0
@previous_failed:
        lda     #0
        sta     previous_valid
        jmp     return0
@read_ok:
        lda     requested_start
        sta     active_start
        lda     #1
        sta     active_valid

@count:
.ifdef CONFIG_NIO_BBC_XRAM_TABLES
        lda     #0
        sta     row_index
        sta     _config_nio_store_buf
@count_loop:
        lda     row_index
        jsr     get_slot_appbuf
        lda     _config_nio_appstore_buf
        beq     :+
        inc     _config_nio_store_buf
:
        inc     row_index
        lda     row_index
        cmp     #PAGE_SIZE
        bne     @count_loop
.else
        lda     #0
        sta     _config_nio_store_buf
        ldx     #0
@count_loop:
        lda     _config_nio_bbc_slots,x
        beq     :+
        inc     _config_nio_store_buf
:
        txa
        clc
        adc     #30
        tax
        cmp     #PAGE_SIZE*30
        bne     @count_loop
.endif
        jsr     restore_refresh_state_ptr
        ldy     #STATE_SLOT_COUNT
        lda     _config_nio_store_buf
        sta     (ptr1),y
        iny
        lda     #0
        sta     (ptr1),y
        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        cmp     #248
        bcs     :+
        ldy     #STATE_SLOTS_MORE
        lda     #1
        sta     (ptr1),y
:
        jmp     return1

; void draw_drive_rows(config_nio_state_t *state)
;
; Draw the four persistent or transient drive mappings. The external state
; implementation lets the shared store buffer hold both the mapping and slot
; records, avoiding two C-stack structures.
_draw_drive_rows:
        lda     #0
        sta     drive_index

drive_loop:
        ldx     #CONFIG_NIO_BBC_SLOTS_DRIVES_X
        lda     drive_index
        clc
        adc     #CONFIG_NIO_BBC_SLOTS_DRIVES_Y
        jsr     goto_xy

        lda     _slots_focus
        bne     drive_not_selected
        lda     drive_index
        cmp     _selected_drive
        bne     drive_not_selected
        lda     #'>'
        bne     write_marker
drive_not_selected:
        lda     #' '
write_marker:
        jsr     OSWRCH
        lda     #'D'
        jsr     OSWRCH
        lda     drive_index
        clc
        adc     #'0'
        jsr     OSWRCH
        lda     #' '
        jsr     OSWRCH

        lda     drive_index
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_bbc_mapping_get
        cmp     #0
        beq     runtime_mapping
        lda     _config_nio_store_buf+MAPPING_VALID
        beq     runtime_mapping

        lda     _config_nio_store_buf+MAPPING_SLOT
        sta     mapping_slot
        lda     _config_nio_store_buf+MAPPING_READONLY
        sta     mapping_readonly

        lda     #'S'
        jsr     OSWRCH
        lda     mapping_slot
        jsr     _put_slot_index
        lda     #' '
        jsr     OSWRCH
        lda     mapping_readonly
        beq     writable_mapping
        lda     #'R'
        bne     write_mode
writable_mapping:
        lda     #'W'
write_mode:
        jsr     OSWRCH
        lda     #' '
        jsr     OSWRCH

        lda     mapping_slot
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_read_slot
        cmp     #0
        beq     empty_slot_name
        lda     _config_nio_store_buf+SLOT_ENABLED
        beq     empty_slot_name

        lda     #<(_config_nio_store_buf+SLOT_URI)
        ldx     #>(_config_nio_store_buf+SLOT_URI)
        jsr     pushax
        jsr     slot_name_width
        jsr     _config_nio_bbc_put_basename
        jmp     next_drive

empty_slot_name:
        lda     #0
        tax
        jsr     pushax
        jsr     slot_name_width
        jsr     _config_nio_bbc_put_fixed
        jmp     next_drive

runtime_mapping:
        ldy     drive_index
        lda     _runtime_offsets,y
        clc
        adc     #<_uri_buf
        sta     ptr1
        lda     #>_uri_buf
        adc     #0
        sta     ptr1+1
        ldy     #0
        lda     (ptr1),y
        beq     no_mapping

        lda     #'B'
        jsr     OSWRCH
        lda     #'O'
        jsr     OSWRCH
        jsr     OSWRCH
        lda     #'T'
        jsr     OSWRCH
        lda     #' '
        jsr     OSWRCH
        lda     ptr1
        ldx     ptr1+1
        jsr     pushax
        lda     #BBC_RUNTIME_NAME_WIDTH
        jsr     _config_nio_bbc_put_basename
        jmp     next_drive

no_mapping:
        lda     #'-'
        jsr     OSWRCH
        jsr     OSWRCH
        lda     #0
        tax
        jsr     pushax
        lda     #CONFIG_NIO_BBC_SLOTS_DRIVES_EMPTY_WIDTH
        jsr     _config_nio_bbc_put_fixed

next_drive:
        inc     drive_index
        lda     drive_index
        cmp     #BBC_DRIVE_COUNT
        beq     drive_done
        jmp     drive_loop
drive_done:
        rts

; The slot prefix gains one character at 10 and again at 100, so reduce the
; basename field by the same amount. Returns the width in A.
slot_name_width:
        lda     mapping_slot
        cmp     #10
        bcs     two_digits
        lda     #CONFIG_NIO_BBC_SLOTS_DRIVES_BASENAME_WIDTH
        rts
two_digits:
        cmp     #100
        bcs     three_digits
        lda     #(CONFIG_NIO_BBC_SLOTS_DRIVES_BASENAME_WIDTH-1)
        rts
three_digits:
        lda     #(CONFIG_NIO_BBC_SLOTS_DRIVES_BASENAME_WIDTH-2)
        rts


; void draw_slot_rows(config_nio_state_t *state)
_draw_slot_rows:
        sta     ptr1
        stx     ptr1+1
        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        sta     slot_start
        lda     #0
        sta     slot_row_index

slot_row_loop:
        ldx     #CONFIG_NIO_BBC_SLOTS_SLOTS_X
        lda     slot_row_index
        clc
        adc     #CONFIG_NIO_BBC_SLOTS_SLOTS_Y
        jsr     goto_xy
        lda     #CONFIG_NIO_BBC_BROWSE_ASSIGN_CLEAR_WIDTH
        jsr     write_spaces

        ldx     #CONFIG_NIO_BBC_SLOTS_SLOTS_X
        lda     slot_row_index
        clc
        adc     #CONFIG_NIO_BBC_SLOTS_SLOTS_Y
        jsr     goto_xy
        lda     _slots_focus
        beq     slot_not_selected
        lda     slot_row_index
        cmp     _selected_slot
        bne     slot_not_selected
        lda     #'>'
        bne     write_slot_marker
slot_not_selected:
        lda     #' '
write_slot_marker:
        jsr     OSWRCH
        lda     #' '
        jsr     OSWRCH
        lda     slot_start
        clc
        adc     slot_row_index
        jsr     _put_slot_index
        lda     #' '
        jsr     OSWRCH

        lda     slot_row_index
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_bbc_slot_get
        cmp     #0
        beq     empty_slot_row
        lda     #<(_config_nio_store_buf+SLOT_URI)
        ldx     #>(_config_nio_store_buf+SLOT_URI)
        jsr     pushax
        lda     #CONFIG_NIO_BBC_SLOTS_SLOTS_URI_WIDTH
        jsr     _config_nio_bbc_put_tail
        jmp     next_slot_row

empty_slot_row:
        lda     #0
        tax
        jsr     pushax
        lda     #CONFIG_NIO_BBC_SLOTS_SLOTS_URI_WIDTH
        jsr     _config_nio_bbc_put_fixed

next_slot_row:
        inc     slot_row_index
        lda     slot_row_index
        cmp     #CONFIG_NIO_BBC_SLOTS_SLOTS_COUNT
        bne     slot_row_loop
        rts

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

_handle_slots:
        sta     slots_saved_key

        ; Tab toggles between drive and slot focus.
        lda     slots_saved_key
        cmp     #$09
        jeq     toggle_focus

        lda     _slots_focus
        jeq     drive_focus


; ===========================================================================
; Slot-list focus
; ===========================================================================

slot_focus:
        ; Test non-ASCII cursor codes before modifying the key.
        lda     slots_saved_key

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
        lda     slots_saved_key
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
        jsr     restore_saved_state_ptr

        ldy     #STATE_SLOTS_MORE
        lda     (ptr1),y
        jeq     return_false

        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        clc
        adc     #8
        sta     (ptr1),y

        jsr     refresh_slot_page
        jsr     redraw_slot_rows
        jmp     return_false


; ---------------------------------------------------------------------------
; Previous slot page
; ---------------------------------------------------------------------------

slot_previous_page:
        jsr     restore_saved_state_ptr

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

        jsr     refresh_slot_page
        jsr     redraw_slot_rows
        jmp     return_false


; ---------------------------------------------------------------------------
; Move selected slot up
; ---------------------------------------------------------------------------

redraw_slot_rows:
        jsr     load_state
        jmp     _draw_slot_rows

slot_up:
        lda     _selected_slot
        jeq     return_false

        sta     slots_old_selection
        dec     _selected_slot

        lda     slots_old_selection
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

        sta     slots_old_selection
        inc     _selected_slot

        lda     slots_old_selection
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

        jsr     restore_saved_state_ptr
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
        jsr     restore_saved_state_ptr

        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        clc
        adc     _selected_slot
        sta     absolute_slot

        ; config_nio_delete_slot(state, absolute_slot)
        jsr     load_state
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
        jsr     refresh_slot_page

        jmp     return_true


; ===========================================================================
; Drive-list focus
; ===========================================================================

drive_focus:
        lda     slots_saved_key

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

        sta     slots_old_selection
        dec     _selected_drive

        lda     slots_old_selection
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

        sta     slots_old_selection
        inc     _selected_drive

        lda     slots_old_selection
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
        beq     focus_was_drives


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

; config_nio_refresh_slots(state)
refresh_slot_page:
        jsr     load_state
        jmp     _config_nio_refresh_slots


; config_nio_save_mappings(state)
save_mappings:
        jsr     load_state
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
        stx     slot_marker_char

        clc
        adc     #CONFIG_NIO_BBC_SLOTS_SLOTS_Y
        pha                             ; preserve calculated y

        lda     #CONFIG_NIO_BBC_SLOTS_SLOTS_X
        jsr     pusha                   ; stacked x argument

        pla                             ; fastcall y argument
        jsr     _gotoxy

        lda     slot_marker_char
        jmp     _cputc


drive_marker:
        stx     slot_marker_char

        clc
        adc     #CONFIG_NIO_BBC_SLOTS_DRIVES_Y
        pha                             ; preserve calculated y

        lda     #CONFIG_NIO_BBC_SLOTS_DRIVES_X
        jsr     pusha                   ; stacked x argument

        pla                             ; fastcall y argument
        jsr     _gotoxy

        lda     slot_marker_char
        jmp     _cputc



; void put_slot_index(uint8_t value)
;
; A = value

_put_slot_index:
        ldx     #$00                    ; hundreds

        cmp     #200
        bcc     @less_than_200

        sbc     #200                    ; carry already set by CMP
        ldx     #2
        bne     @find_tens              ; always

@less_than_200:
        cmp     #100
        bcc     @find_tens

        sbc     #100                    ; carry already set by CMP
        inx                             ; hundreds = 1

@find_tens:
        ldy     #$00                    ; tens

@tens_loop:
        cmp     #10
        bcc     @digits_ready

        sbc     #10                     ; carry set by CMP
        iny
        bne     @tens_loop              ; always for a byte value

@digits_ready:
        ; A = units, Y = tens, X = hundreds.
        ;
        ; Save finished ASCII units and tens before calling cputc,
        ; since cputc may destroy A, X and Y.

        ora     #'0'
        pha                             ; units

        tya
        ora     #'0'
        pha                             ; tens

        txa
        beq     @no_hundreds

        ora     #'0'
        jsr     _cputc

        ; Hundreds was printed, so tens must be printed even when zero.
        pla
        jsr     _cputc

        pla
        jmp     _cputc                  ; print units and return

@no_hundreds:
        pla                             ; tens
        cmp     #'0'
        beq     @units

        jsr     _cputc

@units:
        pla
        jmp     _cputc


; char *runtime_mount_display(uint8_t unit)
;
; Entry:
;   A = unit
;
; Return:
;   AX = display string pointer
;   AX = 0 on failure
;
; This implementation requests one formatted runtime-mount entry and extracts
; the final path component from:
;
;   <unit>: <RO|AUTO> <uri>\n
;
; The BBC request limits text to 240 bytes:
;
;   10-byte header + 240-byte text = 250 bytes
;
; Therefore response parsing can safely use 8-bit offsets, while still
; rejecting a nonzero entries_len high byte.

_refresh_runtime_mounts:
        lda     #$00
        sta     mounts_loop_counter
loop_mounts:
        lda     mounts_loop_counter
        cmp     #BBC_DRIVE_COUNT
        bcs     done_mounts
        jsr     _runtime_mount_display
        inc     mounts_loop_counter
        bne     loop_mounts
done_mounts:
        rts

_runtime_mount_display:

        ; Save the unit directly into both 16-bit request fields:
        ;
        ; first_unit = unit
        ; last_unit  = unit
        ;
        sta     mounts_request+2
        sta     mounts_request+4

        ; Clear this drive's display before querying DiskService.  A failed
        ; LIST_MOUNTS response must not leave a stale tail of a URI (the
        ; shared uri_buf is also used while assigning catalogue slots).
        tay
        lda     _runtime_offsets,y
        clc
        adc     #<_uri_buf
        sta     ptr1
        lda     #>_uri_buf
        adc     #0
        sta     ptr1+1
        ldy     #0
        lda     #0
        sta     (ptr1),y

        ; -------------------------------------------------------------------
        ; fn_bbc_device_call_raw(
        ;     NIO_DEVICE_DISK,
        ;     NIO_DISK_LIST_MOUNTS,
        ;     mounts_request,
        ;     10,
        ;     fnsvc_bbc_resp_buf,
        ;     NIO_DISK_LIST_MOUNTS_RESPONSE,
        ;     &mounts_device_status,
        ;     &mounts_response_len
        ; );
        ;
        ; Standard cc65 fastcall convention:
        ;   all arguments except the final one are pushed in source order;
        ;   the final response_len pointer is passed in AX.
        ; -------------------------------------------------------------------

        lda     #NIO_DEVICE_DISK
        jsr     pusha

        lda     #NIO_DISK_LIST_MOUNTS
        jsr     pusha

        lda     #<mounts_request
        ldx     #>mounts_request
        jsr     pushax

        lda     #10
        ldx     #0
        jsr     pushax

        lda     #<_fnsvc_bbc_resp_buf
        ldx     #>_fnsvc_bbc_resp_buf
        jsr     pushax

        lda     #<NIO_DISK_LIST_MOUNTS_RESPONSE
        ldx     #>NIO_DISK_LIST_MOUNTS_RESPONSE
        jsr     pushax

        lda     #<mounts_device_status
        ldx     #>mounts_device_status
        jsr     pushax

        lda     #<mounts_response_len
        ldx     #>mounts_response_len
        jsr     _fn_bbc_device_call_raw

        ; result != 0
        cmp     #0
        beq     call_ok
        jmp     return0

call_ok:
        ; device_status != 0
        lda     mounts_device_status
        beq     status_ok
        jmp     return0

status_ok:
        ; response_len must contain at least the 10-byte header.
        lda     mounts_response_len+1
        bne     header_present

        lda     mounts_response_len
        cmp     #NIO_DISK_LIST_MOUNTS_HEADER
        bcs     header_present
        jmp     return0

header_present:
        ; Protocol version must be 1.
        lda     _fnsvc_bbc_resp_buf+LIST_VERSION
        cmp     #1
        beq     version_ok
        jmp     return0

version_ok:
        ; Formatted-response flag, bit 1, must be set.
        lda     _fnsvc_bbc_resp_buf+LIST_FLAGS
        and     #$02
        bne     formatted_ok
        jmp     return0

formatted_ok:
        ; There must be at least one entry.
        ;
        ; This matches the original C check of response[6].
        lda     _fnsvc_bbc_resp_buf+LIST_ENTRY_COUNT_LO
        bne     entry_present
        jmp     return0

entry_present:
        ; The protocol length is 16-bit, but this caller requested a maximum
        ; of 240 bytes. Reject a response that cannot be represented by our
        ; byte-offset parser.
        lda     _fnsvc_bbc_resp_buf+LIST_ENTRIES_LEN_HI
        beq     length_high_ok
        jmp     return0

length_high_ok:
        lda     _fnsvc_bbc_resp_buf+LIST_ENTRIES_LEN_LO

        ; Original C requires at least eight bytes of formatted text.
        cmp     #8
        bcs     length_minimum_ok
        jmp     return0

length_minimum_ok:
        ; Reject anything beyond the requested 240-byte budget.
        cmp     #BBC_MOUNTS_PAYLOAD+1
        bcc     length_within_budget
        jmp     return0

length_within_budget:
        ; tmp1 = exclusive end offset:
        ;
        ;   NIO_DISK_LIST_MOUNTS_HEADER + entries_len
        ;
        clc
        adc     #NIO_DISK_LIST_MOUNTS_HEADER
        bcc     end_offset_ok
        jmp     return0

end_offset_ok:
        sta     tmp1

        ; Verify that the received response actually contains the complete
        ; declared text.
        lda     mounts_response_len+1
        bne     response_complete

        lda     mounts_response_len
        cmp     tmp1
        bcs     response_complete
        jmp     return0

response_complete:
        ; -------------------------------------------------------------------
        ; Validate:
        ;
        ;   start[0] == '0' + unit
        ;   start[1] == ':'
        ;   start[2] == ' '
        ; -------------------------------------------------------------------

        lda     mounts_request+2
        clc
        adc     #'0'
        cmp     _fnsvc_bbc_resp_buf+LIST_TEXT
        beq     unit_ok
        jmp     return0

unit_ok:
        lda     _fnsvc_bbc_resp_buf+LIST_TEXT+1
        cmp     #':'
        beq     colon_ok
        jmp     return0

colon_ok:
        lda     _fnsvc_bbc_resp_buf+LIST_TEXT+2
        cmp     #' '
        beq     prefix_ok
        jmp     return0

prefix_ok:
        ; -------------------------------------------------------------------
        ; Calculate:
        ;
        ;   display = &uri_buf[runtime_offsets[unit]]
        ;
        ; runtime_offsets is a uint8_t[] of offsets within uri_buf.
        ; -------------------------------------------------------------------

        lda     mounts_request+2
        tay

        lda     _runtime_offsets,y
        clc
        adc     #<_uri_buf
        sta     ptr1

        lda     #>_uri_buf
        adc     #0
        sta     ptr1+1

        ; Begin immediately after "<unit>: ".
        ldx     #LIST_TEXT+3


; ---------------------------------------------------------------------------
; Skip the access mode: "RO" or "AUTO"
; ---------------------------------------------------------------------------

find_mode_space:
        cpx     tmp1
        bcc     mode_byte_available
        jmp     return0

mode_byte_available:
        lda     _fnsvc_bbc_resp_buf,x
        inx
        cmp     #' '
        bne     find_mode_space


; ---------------------------------------------------------------------------
; Skip spaces between access mode and URI
; ---------------------------------------------------------------------------

skip_spaces:
        cpx     tmp1
        bcc     space_byte_available
        jmp     return0

space_byte_available:
        lda     _fnsvc_bbc_resp_buf,x
        cmp     #' '
        bne     uri_found

        inx
        bne     skip_spaces             ; X cannot wrap in a valid response

uri_found:
        ; tmp2 holds the current basename candidate.
        ;
        ; Initially this is the start of the complete URI.
        stx     tmp2


; ---------------------------------------------------------------------------
; Scan the URI.
;
; Every '/' or ':' moves the candidate basename to the byte following that
; separator.
; ---------------------------------------------------------------------------

scan_uri:
        cpx     tmp1
        bcs     name_end_found

        lda     _fnsvc_bbc_resp_buf,x

        ; Formatted records are newline terminated. Stop before the newline,
        ; rather than including it in the display string.
        cmp     #$0A
        beq     name_end_found

        inx

        cmp     #'/'
        beq     new_name_start

        cmp     #':'
        bne     scan_uri

new_name_start:
        stx     tmp2
        jmp     scan_uri


; ---------------------------------------------------------------------------
; Copy at most BBC_RUNTIME_NAME_WIDTH bytes.
;
; At entry:
;   X    = exclusive end of the filename, or newline offset
;   tmp2 = basename start
;   ptr1 = display destination
; ---------------------------------------------------------------------------

name_end_found:
        stx     tmp1                    ; tmp1 now becomes copy-end offset
        ldx     tmp2
        ldy     #0

copy_name:
        cpx     tmp1
        bcs     terminate

        cpy     #BBC_RUNTIME_NAME_WIDTH
        bcs     terminate

        lda     _fnsvc_bbc_resp_buf,x
        sta     (ptr1),y

        inx
        iny
        bne     copy_name               ; width is necessarily below 256

terminate:
        lda     #0
        sta     (ptr1),y

        ; Return display in AX.
        lda     ptr1
        ldx     ptr1+1
        rts
