        .export _config_nio_bbc_cursor
        .export _config_nio_bbc_clear_line
        .export _config_nio_bbc_put_fixed
        .export _config_nio_bbc_put_tail
        .export _config_nio_bbc_put_basename

        .import popax
        .importzp ptr1, ptr2, tmp1, tmp2

        .include "oslib/os.inc"

        .code

; void __fastcall__ config_nio_bbc_cursor(uint8_t on)
_config_nio_bbc_cursor:
        pha
        lda     #23
        jsr     OSWRCH
        lda     #1
        jsr     OSWRCH
        pla
        beq     @off
        lda     #1
@off:  jsr     OSWRCH
        lda     #0
        ldx     #7
@loop: jsr     OSWRCH
        dex
        bne     @loop
        rts

; void __fastcall__ config_nio_bbc_clear_line(uint8_t row)
_config_nio_bbc_clear_line:
        sta     tmp1
        lda     #31
        jsr     OSWRCH
        lda     #0
        jsr     OSWRCH
        lda     tmp1
        jsr     OSWRCH
        lda     #' '
        ldx     #40
@spc:  jsr     OSWRCH
        dex
        bne     @spc
        lda     #31
        jsr     OSWRCH
        lda     #0
        jsr     OSWRCH
        lda     tmp1
        jmp     OSWRCH

; void config_nio_bbc_put_fixed(const char *s, uint8_t width)
_config_nio_bbc_put_fixed:
        sta     tmp1
        jsr     popax
        sta     ptr1
        stx     ptr1+1
put_fixed_ptr1:
        lda     ptr1
        ora     ptr1+1
        beq     @spaces
@chars:
        lda     tmp1
        beq     @done
        ldy     #0
        lda     (ptr1),y
        beq     @blank_tail
        jsr     OSWRCH
        inc     ptr1
        bne     @next
        inc     ptr1+1
@next: dec     tmp1
        bne     @chars
        rts
@blank_tail:
        lda     #0
        sta     ptr1
        sta     ptr1+1
@spaces:
        lda     tmp1
        beq     @done
        lda     #' '
@spc2: jsr     OSWRCH
        dec     tmp1
        bne     @spc2
@done: rts

; void config_nio_bbc_put_tail(const char *s, uint8_t width)
_config_nio_bbc_put_tail:
        sta     tmp1
        jsr     popax
        sta     ptr1
        stx     ptr1+1
put_tail_ptr1:
        sta     ptr2
        stx     ptr2+1
        ora     ptr1+1
        beq     put_fixed_ptr1

        ldy     #0
@len:  lda     (ptr2),y
        beq     @len_done
        iny
        bne     @len
@len_done:
        sty     tmp2
        cpy     tmp1
        bcc     put_fixed_ptr1
        beq     put_fixed_ptr1
        tya
        sec
        sbc     tmp1
        clc
        adc     ptr1
        sta     ptr1
        bcc     @tail
        inc     ptr1+1
@tail: jmp     put_fixed_ptr1

; void config_nio_bbc_put_basename(const char *s, uint8_t width)
_config_nio_bbc_put_basename:
        sta     tmp1
        jsr     popax
        sta     ptr1
        stx     ptr1+1
        sta     ptr2
        stx     ptr2+1
        ora     ptr1+1
        beq     put_fixed_ptr1

        ldy     #0
@scan: lda     (ptr1),y
        beq     @done
        cmp     #'/'
        bne     @inc
        iny
        lda     (ptr1),y
        dey
        beq     @inc
        lda     ptr1
        clc
        adc     #1
        sta     ptr2
        lda     ptr1+1
        adc     #0
        sta     ptr2+1
@inc:  inc     ptr1
        bne     @scan
        inc     ptr1+1
        bne     @scan
@done: lda     ptr2
        sta     ptr1
        lda     ptr2+1
        sta     ptr1+1
        lda     ptr2
        ldx     ptr2+1
        jmp     put_tail_ptr1
