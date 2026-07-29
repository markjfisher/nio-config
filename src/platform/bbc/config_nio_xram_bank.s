        .export         _config_nio_xram_begin
        .export         _config_nio_xram_end

ROMSEL_CURRENT := $F4
ROMSEL         := $FE30

        .bss
saved_romsel:
        .res    1
saved_status:
        .res    1

        .code

; void __fastcall__ config_nio_xram_begin(uint8_t bank)
; Selects a sideways RAM bank while preserving MOS' ROMSEL shadow.
_config_nio_xram_begin:
        tax
        php
        pla
        sta     saved_status
        sei
        lda     ROMSEL_CURRENT
        sta     saved_romsel
        stx     ROMSEL_CURRENT
        stx     ROMSEL
        rts

; void config_nio_xram_end(void)
_config_nio_xram_end:
        lda     saved_romsel
        sta     ROMSEL_CURRENT
        sta     ROMSEL
        lda     saved_status
        pha
        plp
        rts
