        .export _config_nio_compose_uri
        .export _config_nio_bbc_copy_slot_display_uri

        .import popax
        .importzp ptr1, ptr2, ptr3, ptr4, tmp1, tmp2, tmp3, tmp4

FLAG_SCHEME = $01
FLAG_SLASH  = $02
FLAG_SEP    = $04

        .code

return0:
        lda     #0
        tax
        rts

return1:
        lda     #1
        ldx     #0
        rts

; Append A to the output buffer, preserving room for a trailing NUL.
append_char:
        ldx     tmp2
        inx
        cpx     tmp1
        bcs     @fail
        ldy     tmp2
        sta     (ptr2),y
        inc     tmp2
        ldy     tmp2
        lda     #0
        sta     (ptr2),y
        clc
        rts
@fail: sec
        rts

append_string:
        lda     #0
        sta     tmp4
@loop:  ldy     tmp4
        lda     (ptr1),y
        beq     @done
        jsr     append_char
        bcs     @fail
        inc     tmp4
        bne     @loop
@done:  clc
        rts
@fail: sec
        rts

append_tnfs_prefix:
        lda     #'t'
        jsr     append_char
        bcs     @fail
        lda     #'n'
        jsr     append_char
        bcs     @fail
        lda     #'f'
        jsr     append_char
        bcs     @fail
        lda     #'s'
        jsr     append_char
        bcs     @fail
        lda     #':'
        jsr     append_char
        bcs     @fail
        lda     #'/'
        jsr     append_char
        bcs     @fail
        lda     #'/'
        jsr     append_char
@fail: rts

scan_host:
        lda     #0
        sta     tmp3
        sta     tmp4
        tay
@loop:  lda     (ptr1),y
        beq     @done
        sta     tmp4
        cmp     #':'
        bne     @not_colon
        lda     tmp3
        and     #FLAG_SEP
        bne     @advance
        lda     tmp3
        ora     #FLAG_SCHEME
        sta     tmp3
        bne     @advance
@not_colon:
        cmp     #'/'
        beq     @mark_sep
        cmp     #$5C
        bne     @advance
@mark_sep:
        lda     tmp3
        ora     #FLAG_SEP
        sta     tmp3
@advance:
        iny
        bne     @loop
@done:  lda     tmp4
        cmp     #'/'
        beq     @slash_done
        lda     tmp3
        ora     #FLAG_SLASH
        sta     tmp3
@slash_done:
        rts

ptr1_from_path:
        lda     ptr4
        sta     ptr1
        lda     ptr4+1
        sta     ptr1+1
        rts

ptr1_from_leaf:
        lda     ptr3
        sta     ptr1
        lda     ptr3+1
        sta     ptr1+1
        rts

ptr_is_empty:
        lda     ptr1
        ora     ptr1+1
        beq     @empty
        ldy     #0
        lda     (ptr1),y
        beq     @empty
        lda     #1
        rts
@empty:
        lda     #0
        rts

append_slash_if_needed:
        lda     tmp3
        and     #FLAG_SLASH
        beq     @ok
        lda     #'/'
        jsr     append_char
        bcs     @fail
@ok:   clc
        rts
@fail: sec
        rts

; int config_nio_compose_uri(const char *host, const char *path,
;                            const char *leaf, char *out, uint16_t cap)
_config_nio_compose_uri:
        sta     tmp1
        txa
        beq     @cap_ok
        lda     #$FF
        sta     tmp1
@cap_ok:
        jsr     popax
        sta     ptr2            ; out
        stx     ptr2+1
        jsr     popax
        sta     ptr3            ; leaf
        stx     ptr3+1
        jsr     popax
        sta     ptr4            ; path
        stx     ptr4+1
        jsr     popax
        sta     ptr1            ; host
        stx     ptr1+1

        lda     ptr1
        ora     ptr1+1
        beq     @bad
        lda     ptr2
        ora     ptr2+1
        beq     @bad
        lda     tmp1
        beq     @bad
        ldy     #0
        lda     (ptr1),y
        beq     @bad

        lda     #0
        sta     tmp2
        sta     (ptr2),y

        jsr     scan_host
        lda     tmp3
        and     #FLAG_SCHEME
        bne     @host
        jsr     append_tnfs_prefix
        bcs     @bad

@host: jsr     append_string
        bcs     @bad

        jsr     ptr1_from_path
        jsr     ptr_is_empty
        beq     @no_path
        jsr     append_slash_if_needed
        bcs     @bad
        jsr     append_string
        bcs     @bad
        jmp     @leaf

@no_path:
        jsr     ptr1_from_leaf
        jsr     ptr_is_empty
        beq     @no_path_no_leaf
        jsr     append_slash_if_needed
        bcs     @bad
        jmp     @leaf

@no_path_no_leaf:
        lda     tmp3
        and     #FLAG_SCHEME
        bne     @leaf
        jsr     append_slash_if_needed
        bcs     @bad

@leaf: jsr     ptr1_from_leaf
        jsr     ptr_is_empty
        beq     @ok
        lda     tmp2
        beq     @append_leaf
        tay
        dey
        lda     (ptr2),y
        cmp     #'/'
        beq     @append_leaf
        lda     #'/'
        jsr     append_char
        bcs     @bad
@append_leaf:
        jsr     ptr1_from_leaf
        jsr     append_string
        bcs     @bad
@ok:   jmp     return1
@bad:  jmp     return0

copy_n:
        lda     tmp2
        beq     @term
        ldy     #0
@loop:  lda     (ptr3),y
        sta     (ptr2),y
        iny
        cpy     tmp2
        bne     @loop
@term:  lda     #0
        sta     (ptr2),y
        rts

ptr3_from_src:
        lda     ptr1
        sta     ptr3
        lda     ptr1+1
        sta     ptr3+1
        rts

ptr3_add_y:
        tya
        clc
        adc     ptr3
        sta     ptr3
        bcc     @done
        inc     ptr3+1
@done: rts

; void config_nio_bbc_copy_slot_display_uri(char *dst, uint16_t cap,
;                                           const char *src)
_config_nio_bbc_copy_slot_display_uri:
        sta     ptr1            ; src
        stx     ptr1+1
        jsr     popax
        sta     tmp1            ; cap low, clamped for BBC buffers
        txa
        beq     @got_cap
        lda     #$FF
        sta     tmp1
@got_cap:
        jsr     popax
        sta     ptr2            ; dst
        stx     ptr2+1

        lda     ptr2
        ora     ptr2+1
        beq     @done
        lda     tmp1
        beq     @done
        ldy     #0
        tya
        sta     (ptr2),y
        lda     ptr1
        ora     ptr1+1
        beq     @done
        lda     (ptr1),y
        beq     @done

        jsr     ptr3_from_src
        ldy     #0
@scheme_scan:
        lda     (ptr1),y
        beq     @shown_ready
        cmp     #':'
        bne     @scheme_next
        iny
        lda     (ptr1),y
        cmp     #'/'
        bne     @shown_src
        iny
        lda     (ptr1),y
        cmp     #'/'
        bne     @shown_src
        iny
        jsr     ptr3_from_src
        jsr     ptr3_add_y
        ldy     #0
@authority:
        lda     (ptr3),y
        beq     @shown_src
        cmp     #'/'
        beq     @shown_ready
        inc     ptr3
        bne     @authority
        inc     ptr3+1
        bne     @authority
@scheme_next:
        iny
        bne     @scheme_scan

@shown_src:
        jsr     ptr3_from_src

@shown_ready:
        ldy     #0
@len_loop:
        lda     (ptr3),y
        beq     @len_done
        iny
        bne     @len_loop
@len_done:
        sty     tmp2            ; length

        tya
        cmp     tmp1
        bcs     @truncate
        jmp     copy_n
@truncate:
        sec
        lda     tmp1
        sbc     #1
        sta     tmp2
        tya
        sec
        sbc     tmp2
        tay
        jsr     ptr3_add_y
        jmp     copy_n

@done: rts
