        .export   _label_width2

        .import   return0
        .importzp ptr1


        .code

; unsigned char __near__ label_width (const char *label)
; original C implementation 63 bytes, this is 24 without X set
_label_width2:
        sta     ptr1
        stx     ptr1+1
        ora     ptr1+1                  ; check if label is null
        bne     @have_label
        jmp     return0

@have_label:
        ldy     #$00
@len_loop:
        lda     (ptr1), y
        beq     @string_end
        iny
        cpy     #12                     ; don't go over 12, TODO: turn to a constant somewhere
        bcc     @len_loop

@string_end:
;         ldx     #$00                    ; caller probably only reads A, but let's make this 16 bit
        tya
        rts

