; CONFNIO occupies language RAM, including BBC BASIC's program area. Returning
; directly to the existing language instance leaves it with corrupt state.
;
; crt0 calls this after destructors, vectors, cursor state, and display state
; have been restored. Re-enter the current language so it can initialise fresh.

        .export bbc_exit_hook

        .import OSBYTE
        .import _clrscr

        .include "oslib/os.inc"

        .code

bbc_exit_hook:
        ; CONFNIO owns the full-screen interface, so clear it before handing
        ; control to a freshly initialised language instance. This must remain
        ; application-specific: ordinary BBC executables retain their output.
        jsr     _clrscr

        ; OSBYTE 252 reads the current language ROM number when X=0, Y=$FF.
        lda     #$FC
        ldx     #$00
        ldy     #$FF
        jsr     OSBYTE

        ; OSBYTE 142 enters language ROM X and does not return.
        lda     #$8E
        jmp     OSBYTE
