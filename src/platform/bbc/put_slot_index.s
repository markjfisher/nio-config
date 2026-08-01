.export _put_slot_index

.import _cputc

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