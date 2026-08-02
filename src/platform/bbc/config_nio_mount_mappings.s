; BBC implementation of config_nio_mount_mappings().
;
; The external BBC state model stores mappings and slots through the table and
; slot-catalog services.  The app-store scratch buffer is reused for temporary
; records.  The writable command template needs only its three slot digits and
; drive digit changed for each mapping.

        .export _config_nio_mount_mappings

        .import OSCLI
        .import _config_nio_bbc_mapping_get
        .import _config_nio_read_slot
        .import _config_nio_store_buf
        .import pusha
        .import return0, return1

FNCTL_MAX_UNITS = 8

MAPPING_VALID = 0
MAPPING_SLOT  = 1
SLOT_ENABLED  = 0
SLOT_URI      = 1

        .data
mount_cmd:
        .byte   "FMOUNT 000 0", $0D     ; OSCLI consumes a CR-terminated line

        .bss
mounted_count:  .res 1

        .code

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
