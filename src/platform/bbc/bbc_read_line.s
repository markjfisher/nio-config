        .export _bbc_read_line

        .import _cursor, popa, popax

        .include "oslib/os.inc"

OSWORD_READ_LINE = $00

.bss
line_block:      .res 5
old_cursor:      .res 1

.code

; int __fastcall__ bbc_read_line(char* buf, unsigned char size,
;                                unsigned char min_char, unsigned char max_char);
;
; cc65 calling convention here:
;   A    = max_char
;   c_sp = min_char, size, buf_lo, buf_hi
;
.proc _bbc_read_line
        sta     line_block+4

        jsr     popa
        sta     line_block+2

        jsr     popa
        sta     line_block+3

        jsr     popax
        sta     line_block
        stx     line_block+1

        lda     #1
        jsr     _cursor
        sta     old_cursor

        lda     #OSWORD_READ_LINE
        ldx     #<line_block
        ldy     #>line_block
        jsr     OSWORD

        lda     old_cursor
        jsr     _cursor

        lda     #1
        ldx     #0
        rts
.endproc
