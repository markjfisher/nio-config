        .export _config_nio_bbc_decompress_template

        .importzp ptr1, ptr2, tmp1

SCREEN_BASE = $7C00

        .code

; void __fastcall__ config_nio_bbc_decompress_template(const uint8_t *src)
_config_nio_bbc_decompress_template:
        sta     ptr1
        stx     ptr1+1
        lda     #<SCREEN_BASE
        sta     ptr2
        lda     #>SCREEN_BASE
        sta     ptr2+1
        ldx     #$00

next_token:
        ldy     #$00
        lda     (ptr1),y
        beq     done
        bmi     copy_previous_token

        tay
        inc     ptr1
        bne     raw_loop
        inc     ptr1+1
raw_loop:
        dey
        bmi     next_token
        lda     (ptr1,x)
        sta     (ptr2,x)
        inc     ptr1
        bne     :+
        inc     ptr1+1
:       inc     ptr2
        bne     raw_loop
        inc     ptr2+1
        bne     raw_loop

copy_previous_token:
        and     #$7F
        clc
        adc     #$02
        sta     tmp1
        ldy     #$01
        lda     (ptr1),y
        tay
        clc
        lda     ptr1
        adc     #$02
        sta     ptr1
        bcc     copy_previous_loop
        inc     ptr1+1

copy_previous_loop:
        dec     ptr2+1
        lda     (ptr2),y
        inc     ptr2+1
        sta     (ptr2,x)
        inc     ptr2
        bne     :+
        inc     ptr2+1
:       dec     tmp1
        bne     copy_previous_loop
        beq     next_token

done:
        rts
