; BBC implementation of config_nio_mount_mappings().
;
; The external BBC state model stores mappings and slots through the table and
; slot-catalog services.  The app-store scratch buffer is reused for the
; temporary records and the short *FMOUNT command; only three bytes of private
; BSS are needed for loop bookkeeping.

        .macpack longbranch

        .export _config_nio_mount_mappings

        .import _bbc_oscli
        .import _config_nio_bbc_mapping_get
        .import _config_nio_read_slot
        .import _config_nio_store_buf
        .import pusha
        .import return0, return1
        .importzp tmp1, tmp4

FNCTL_MAX_UNITS = 8

MAPPING_VALID = 0
MAPPING_SLOT  = 1
SLOT_ENABLED  = 0
SLOT_URI      = 1

        .bss
current_unit:   .res 1
mounted_count:  .res 1
current_slot:   .res 1

        .code

; int config_nio_mount_mappings(config_nio_state_t *state)
;   A/X = state pointer (fastcall)
_config_nio_mount_mappings:
        ; The state pointer is unused by the external model, but preserve the
        ; C function's null-pointer result.
        ora     #0
        bne     state_ok
        txa
        jeq     return0
state_ok:
        lda     #0
        sta     current_unit
        sta     mounted_count

unit_loop:
        ; config_nio_bbc_mapping_get(unit, appstore scratch)
        lda     current_unit
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_bbc_mapping_get
        cmp     #0
        jeq     next_unit

        lda     _config_nio_store_buf+MAPPING_VALID
        jeq     next_unit
        lda     _config_nio_store_buf+MAPPING_SLOT
        sta     current_slot            ; preserve slot across read_slot

        ; config_nio_read_slot(slot, appstore scratch)
        lda     current_slot
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _config_nio_read_slot
        cmp     #0
        jeq     next_unit
        lda     _config_nio_store_buf+SLOT_ENABLED
        jeq     next_unit
        lda     _config_nio_store_buf+SLOT_URI
        jeq     next_unit

        ; Build "FMOUNT hts u\r".  Slot indices are bytes, so repeated
        ; subtraction is smaller than pulling in decimal division helpers.
        lda     current_slot
        sta     tmp1
        lda     #0
        sta     tmp4                    ; hundreds
hundreds_loop:
        lda     tmp1
        cmp     #100
        bcc     hundreds_done
        sec
        sbc     #100
        sta     tmp1
        inc     tmp4
        bne     hundreds_loop
hundreds_done:
        lda     tmp4
        ora     #'0'
        sta     _config_nio_store_buf+7
        lda     #0
        sta     tmp4                    ; reuse as tens
tens_loop:
        lda     tmp1
        cmp     #10
        bcc     tens_done
        sec
        sbc     #10
        sta     tmp1
        inc     tmp4
        bne     tens_loop
tens_done:
        lda     #'F'
        sta     _config_nio_store_buf+0
        lda     #'M'
        sta     _config_nio_store_buf+1
        lda     #'O'
        sta     _config_nio_store_buf+2
        lda     #'U'
        sta     _config_nio_store_buf+3
        lda     #'N'
        sta     _config_nio_store_buf+4
        lda     #'T'
        sta     _config_nio_store_buf+5
        lda     #' '
        sta     _config_nio_store_buf+6
        lda     tmp4
        ora     #'0'
        sta     _config_nio_store_buf+8
        lda     tmp1
        ora     #'0'
        sta     _config_nio_store_buf+9
        lda     #' '
        sta     _config_nio_store_buf+10
        lda     current_unit
        ora     #'0'
        sta     _config_nio_store_buf+11
        lda     #$0D
        sta     _config_nio_store_buf+12
        lda     #0
        sta     _config_nio_store_buf+13

        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jsr     _bbc_oscli
        inc     mounted_count

next_unit:
        inc     current_unit
        lda     current_unit
        cmp     #FNCTL_MAX_UNITS
        jne     unit_loop
        lda     mounted_count
        jne     return1
        jmp     return0
