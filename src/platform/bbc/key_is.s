.export  _key_is_next_page
.export  _key_is_previous_page

.include "constants.inc"

; uint8_t key_is_next_page(char key)
;
; key arrives in AX:
;   A = low byte
;   X = high byte

_key_is_next_page:

        cmp     #CH_CURS_RIGHT
        beq     true

        ora     #$20
        cmp     #'n'
        bne     false

true:
        lda     #$01
        rts

false:
        lda     #$00
        rts


; uint8_t key_is_previous_page(char key)

_key_is_previous_page:

        cmp     #CH_CURS_LEFT
        beq     true

        ora     #$20
        cmp     #'p'
        bne     false
        beq     true
