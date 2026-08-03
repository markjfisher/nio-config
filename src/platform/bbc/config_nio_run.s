; void config_nio_run(config_nio_state_t *state)
;
; cc65 fastcall entry:
;   A = low byte of state
;   X = high byte of state

.export _config_nio_run
.export load_state

.importzp c_sp
.importzp tmp1

.import pushax
.import incsp2

.import _mode7
.import _cgetc

.import _show_hosts
.import _draw_browse
.import _draw_slots

.import _handle_hosts
.import _handle_browse
.import _handle_slots

.import _config_nio_bbc_invalidate_slot_cache
.import _refresh_runtime_mounts
.import _config_nio_refresh_slots
.import _config_nio_mount_mappings

.import _current_screen
.import _selected_host
.import _hosts_start
.import _selected_drive
.import _selected_slot
.import _assign_slot_start
.import _slots_focus

.include "bbc_keycodes.inc"

SCREEN_HOSTS  = 0
SCREEN_BROWSE = 1
SCREEN_SLOTS  = 2

.segment "CODE"

_config_nio_run:

        ; Preserve state for the lifetime of this routine:
        ;
        ;   c_sp + 0 = state low
        ;   c_sp + 1 = state high
        ;
        jsr     pushax

        jsr     _mode7

        ; SCREEN_HOSTS is zero, so initialise all UI state together.
        lda     #$00
        sta     _current_screen
        sta     _selected_host
        sta     _hosts_start
        sta     _selected_drive
        sta     _selected_slot
        sta     _assign_slot_start
        sta     _slots_focus

        jmp     redraw_hosts


mount_and_exit:
        jsr     load_state
        jsr     _config_nio_mount_mappings

        ; Return value deliberately ignored.
        ; fall into exit...

; ---------------------------------------------------------------------------
; Exit
; ---------------------------------------------------------------------------

exit:
        ; Remove the saved state pointer and return.
        jmp     incsp2

; ---------------------------------------------------------------------------
; Main keyboard loop
; ---------------------------------------------------------------------------

input_loop:
        jsr     _cgetc

        ; Keep the original key because ORA #$20 is only for command
        ; dispatch. Cursor-key values must reach the screen handlers unchanged.
        sta     tmp1

        cmp     #CH_ESC
        beq     exit

        ; Fold ASCII uppercase to lowercase.
        ora     #$20

        cmp     #'q'
        beq     exit

        cmp     #'h'
        beq     select_hosts

        cmp     #'s'
        beq     select_slots

        cmp     #'m'
        beq     mount_and_exit

        ; It was not a global command. Dispatch the original key to the
        ; handler for the current screen.
        lda     _current_screen
        beq     handle_hosts

        cmp     #SCREEN_BROWSE
        beq     handle_browse

        ; Any other screen is the slots screen.


; ---------------------------------------------------------------------------
; Per-screen input handlers
;
; Signatures:
;
;   uint8_t handle_*(config_nio_state_t *state, int key)
;
; state is pushed onto the C stack; key is passed in AX as the final
; fastcall argument.
; ---------------------------------------------------------------------------

handle_slots:
        jsr     push_state

        lda     tmp1
        ldx     #$00
        jsr     _handle_slots
        jmp     handle_result


handle_browse:
        jsr     push_state

        lda     tmp1
        ldx     #$00
        jsr     _handle_browse
        jmp     handle_result


handle_hosts:
        jsr     push_state

        lda     tmp1
        ldx     #$00
        jsr     _handle_hosts


handle_result:
        ; Handler return value is uint8_t in A.
        cmp     #$00
        beq     input_loop

        ; Nonzero means redraw the active screen.


; ---------------------------------------------------------------------------
; Redraw dispatch
; ---------------------------------------------------------------------------

redraw_current:
        lda     _current_screen
        beq     redraw_hosts

        cmp     #SCREEN_BROWSE
        beq     redraw_browse

        ; Otherwise redraw slots.


redraw_slots:
        jsr     load_state
        jsr     _draw_slots
        jmp     input_loop


redraw_browse:
        jsr     load_state
        jsr     _draw_browse
        jmp     input_loop


redraw_hosts:
        jsr     load_state
        jsr     _show_hosts
        jmp     input_loop


; ---------------------------------------------------------------------------
; Global commands
; ---------------------------------------------------------------------------

select_hosts:
        lda     #SCREEN_HOSTS
        sta     _current_screen
        jmp     redraw_hosts


select_slots:
        lda     #SCREEN_SLOTS
        sta     _current_screen

        ; Runtime mount responses share the slot-cache response buffer.
        jsr     _config_nio_bbc_invalidate_slot_cache
        jsr     _refresh_runtime_mounts

        jsr     load_state
        jsr     _config_nio_refresh_slots

        ; Return value deliberately ignored.
        jmp     redraw_slots


; ---------------------------------------------------------------------------
; Internal helpers
; ---------------------------------------------------------------------------

; Load the persistent state pointer into AX.
;
; Entry:
;   c_sp + 0 = state low
;   c_sp + 1 = state high
;
; Exit:
;   A = state low
;   X = state high
;
load_state:
        ldy     #$01
        lda     (c_sp),y
        tax
        dey
        lda     (c_sp),y
        rts


; Push another copy of state as the first argument to a two-argument
; fastcall function.
;
; The called handle_* function consumes this copied argument, leaving the
; persistent state pointer at c_sp unchanged.
;
push_state:
        jsr     load_state
        jmp     pushax
