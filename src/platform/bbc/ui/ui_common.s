.export goto_xy
.export return_false
.export return_true
.export write_spaces

.import OSWRCH

.import incsp2
.import pusha

.import _gotoxy


; ===========================================================================
; Write A spaces. OSWRCH preserves X on the BBC MOS interface.
; ===========================================================================

write_spaces:
        tax
        lda     #' '
write_space_loop:
        jsr     OSWRCH
        dex
        bne     write_space_loop
        rts

; ===========================================================================
; Shared return paths
;
; incsp2 removes the original stacked state pointer. For a uint8_t result,
; the return value is in A.
; ===========================================================================

return_false:
        lda     #0
        jmp     incsp2

return_true:
        lda     #1
        jmp     incsp2

; X = column, A = row. gotoxy() takes its first byte on the C stack and its
; final byte in A, so the hardware stack safely preserves the row around pusha.
goto_xy:
        pha
        txa
        jsr     pusha
        pla
        jmp     _gotoxy