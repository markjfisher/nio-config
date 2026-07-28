        .export _config_nio_bbc_parent_path
        .export _config_nio_bbc_enter_dir

        .import popax
        .importzp ptr1, ptr2, ptr3, tmp1, tmp2, tmp3

CONFIG_NIO_PATH_MAX = 160

        .code

return0:
        lda     #0
        tax
        rts

return1:
        lda     #1
        ldx     #0
        rts

; void __fastcall__ config_nio_bbc_parent_path(char *path)
_config_nio_bbc_parent_path:
        sta     ptr1
        stx     ptr1+1
        ora     ptr1+1
        beq     @done
        jsr     path_len

@trim_slash:
        lda     tmp1
        beq     @done
        tay
        dey
        lda     (ptr1),y
        cmp     #'/'
        bne     @trim_name
        lda     #0
        sta     (ptr1),y
        dec     tmp1
        jmp     @trim_slash

@trim_name:
        lda     tmp1
        beq     @done
        tay
        dey
        lda     (ptr1),y
        cmp     #'/'
        beq     @done
        lda     #0
        sta     (ptr1),y
        dec     tmp1
        jmp     @trim_name

@done:
        rts

; int config_nio_bbc_enter_dir(char *path, const char *name)
_config_nio_bbc_enter_dir:
        sta     ptr2                    ; name
        stx     ptr2+1
        jsr     popax
        sta     ptr1                    ; path
        stx     ptr1+1
        lda     ptr1
        ora     ptr1+1
        beq     return0
        lda     ptr2
        ora     ptr2+1
        beq     return0

        jsr     path_len
        jsr     name_len
        bcs     return0

        lda     tmp1
        clc
        adc     tmp2
        bcs     return0
        clc
        adc     #2
        bcs     return0
        cmp     #CONFIG_NIO_PATH_MAX+1
        bcs     return0

        lda     ptr1
        clc
        adc     tmp1
        sta     ptr3
        lda     ptr1+1
        adc     #0
        sta     ptr3+1

        lda     tmp1
        beq     @copy_name
        tay
        dey
        lda     (ptr1),y
        cmp     #'/'
        beq     @copy_name
        lda     #'/'
        ldy     #0
        sta     (ptr3),y
        inc     ptr3
        bne     @copy_name
        inc     ptr3+1

@copy_name:
        ldy     #0
@copy_loop:
        cpy     tmp2
        beq     @finish
        lda     (ptr2),y
        sta     (ptr3),y
        iny
        bne     @copy_loop

@finish:
        lda     #'/'
        sta     (ptr3),y
        iny
        lda     #0
        sta     (ptr3),y
        jmp     return1

path_len:
        ldy     #0
@loop:
        lda     (ptr1),y
        beq     @done
        iny
        cpy     #CONFIG_NIO_PATH_MAX
        bcc     @loop
@done:
        sty     tmp1
        rts

name_len:
        ldy     #0
@loop:
        lda     (ptr2),y
        beq     @done
        iny
        cpy     #CONFIG_NIO_PATH_MAX
        bcc     @loop
        sec
        rts
@done:
        sty     tmp2
        clc
        rts
