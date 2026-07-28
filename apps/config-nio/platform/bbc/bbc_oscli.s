        .export _bbc_oscli

        .include "oslib/os.inc"

.code

.proc _bbc_oscli
        pha
        txa
        tay
        pla
        tax
        jmp     OSCLI
.endproc
