        .export _fnsvc_set_mount
        .export _fnsvc_get_mount

        .import popa, popax
        .import _fn_bbc_osword78, _fn_bbc_status_to_result
        .import _fnsvc_bbc_last_error, _fnsvc_bbc_last_status
        .import _fnsvc_bbc_last_raw_error
        .import _fnsvc_bbc_last_response_len
        .importzp ptr1, ptr2, ptr3, tmp1, tmp2, tmp3, tmp4

FN_OK                   = $00
FN_ERR_INVALID          = $02
FN_BBC_STATUS_OK        = $00

FN_BBC_REASON_DEVICE_CALL = $06
NIO_DEVICEID_FUJI       = $70
NIO_FUJI_GET_MOUNT      = $FB
NIO_FUJI_SET_MOUNT      = $FC
FNCTL_MAX_UNITS         = 8
FNSVC_MOUNT_URI_MAX     = 128
FNSVC_MOUNT_MODE_OFF    = 130
FNSVC_MOUNT_MODE_MAX    = 4
BBC_RESP_BUF_SIZE       = 130

FNSVC_ERR_NONE          = 0
FNSVC_ERR_TRANSPORT     = 3
FNSVC_ERR_STATUS        = 4
FNSVC_ERR_SHORT_RESPONSE = 6

        .bss
call_block:
        .res    16
mount_ptr:
        .res    2
_fnsvc_bbc_req_buf:
        .res    170
_fnsvc_bbc_resp_buf:
        .res    BBC_RESP_BUF_SIZE

        .code

return0:
        lda     #0
        tax
        rts

return1:
        lda     #1
        ldx     #0
        rts

; int fnsvc_set_mount(uint8_t slot, const char *uri, const char *mode, uint8_t enabled)
_fnsvc_set_mount:
        sta     tmp1                    ; enabled
        jsr     popax                   ; mode
        sta     ptr2
        stx     ptr2+1
        jsr     popax                   ; uri
        sta     ptr1
        stx     ptr1+1
        jsr     popa                    ; slot
        sta     tmp2

        cmp     #FNCTL_MAX_UNITS
        bcc     @slot_ok
        jmp     @bad
@slot_ok:
        lda     ptr1
        ora     ptr1+1
        bne     @uri_ok
        lda     #<empty
        sta     ptr1
        lda     #>empty
        sta     ptr1+1
@uri_ok:
        lda     ptr2
        ora     ptr2+1
        bne     @mode_ok
        lda     #<empty
        sta     ptr2
        lda     #>empty
        sta     ptr2+1
@mode_ok:
        jsr     strnlen_uri
        bcc     @uri_len_ok
        jmp     @bad
@uri_len_ok:
        sta     tmp3                    ; uri_len
        jsr     strnlen_mode
        bcc     @mode_len_ok
        jmp     @bad
@mode_len_ok:
        sta     tmp4                    ; mode_len

        lda     tmp3
        clc
        adc     tmp4
        adc     #4
        bcc     @size_carry_ok
        jmp     @bad
@size_carry_ok:
        cmp     #171                    ; BBC_REQ_BUF_SIZE + 1
        bcc     @size_ok
        jmp     @bad
@size_ok:

        ldy     #0
        lda     tmp2                    ; slot
        sta     _fnsvc_bbc_req_buf,y
        iny
        lda     tmp1
        beq     @disabled
        lda     #1
@disabled:
        sta     _fnsvc_bbc_req_buf,y
        iny
        lda     tmp3
        sta     _fnsvc_bbc_req_buf,y
        iny

        lda     #<(_fnsvc_bbc_req_buf+3)
        sta     ptr3
        lda     #>(_fnsvc_bbc_req_buf+3)
        sta     ptr3+1
        jsr     copy_uri

        ldy     tmp3
        iny
        iny
        iny
        lda     tmp4
        sta     _fnsvc_bbc_req_buf,y
        iny

        tya
        clc
        adc     #<_fnsvc_bbc_req_buf
        sta     ptr3
        lda     #0
        adc     #>_fnsvc_bbc_req_buf
        sta     ptr3+1
        jsr     copy_mode

        jsr     init_call_block
        lda     tmp3                    ; request length
        clc
        adc     tmp4
        adc     #4
        sta     call_block+7
        lda     #0
        sta     call_block+8

        lda     #<call_block
        ldx     #>call_block
        jsr     _fn_bbc_osword78
        cmp     #FN_BBC_STATUS_OK
        beq     @rom_ok
        jsr     _fn_bbc_status_to_result
        sta     _fnsvc_bbc_last_raw_error
        jmp     return0
@rom_ok:
        lda     #0
        sta     _fnsvc_bbc_last_raw_error
        lda     call_block+4
        beq     @ok
        jmp     return0
@ok:   jmp     return1
@bad:  jmp     return0

; int fnsvc_get_mount(uint8_t slot, fnsvc_mount_t *mount)
_fnsvc_get_mount:
        sta     ptr1                    ; mount
        stx     ptr1+1
        sta     mount_ptr
        stx     mount_ptr+1
        jsr     popa                    ; slot
        sta     tmp1

        lda     ptr1
        ora     ptr1+1
        bne     @mount_ptr_ok
        jmp     @bad
@mount_ptr_ok:
        lda     tmp1
        cmp     #FNCTL_MAX_UNITS
        bcc     @get_slot_ok
        jmp     @bad
@get_slot_ok:

        lda     #FNSVC_ERR_NONE
        sta     _fnsvc_bbc_last_error
        ldy     #0
        tya
        sta     (ptr1),y                ; enabled
        iny
        sta     (ptr1),y                ; uri[0]
        ldy     #FNSVC_MOUNT_MODE_OFF
        sta     (ptr1),y                ; mode[0]

        lda     tmp1
        sta     _fnsvc_bbc_req_buf
        jsr     init_call_block
        lda     #NIO_FUJI_GET_MOUNT
        sta     call_block+3
        lda     #1
        sta     call_block+7
        lda     #0
        sta     call_block+8

        lda     #<call_block
        ldx     #>call_block
        jsr     _fn_bbc_osword78
        cmp     #FN_BBC_STATUS_OK
        beq     @rom_ok
        jsr     _fn_bbc_status_to_result
        sta     _fnsvc_bbc_last_raw_error
        lda     #FNSVC_ERR_TRANSPORT
        sta     _fnsvc_bbc_last_error
        jmp     return0
@rom_ok:
        lda     mount_ptr
        sta     ptr1
        lda     mount_ptr+1
        sta     ptr1+1
        lda     #0
        sta     _fnsvc_bbc_last_raw_error
        lda     call_block+4
        sta     _fnsvc_bbc_last_status
        lda     call_block+13
        sta     _fnsvc_bbc_last_response_len
        sta     tmp3                    ; response length low
        lda     call_block+14
        sta     _fnsvc_bbc_last_response_len+1
        beq     @status_check
        lda     #$FF                    ; high byte should not occur with 130 cap
        sta     tmp3
@status_check:
        lda     _fnsvc_bbc_last_status
        beq     @status_ok
        lda     #FNSVC_ERR_STATUS
        sta     _fnsvc_bbc_last_error
        jmp     return0
@status_ok:
        lda     tmp3
        cmp     #4
        bcs     @len_ok
        lda     #FNSVC_ERR_SHORT_RESPONSE
        sta     _fnsvc_bbc_last_error
        jmp     return0
@len_ok:
        lda     _fnsvc_bbc_resp_buf
        cmp     tmp1
        beq     @slot_ok2
        lda     #FNSVC_ERR_SHORT_RESPONSE
        sta     _fnsvc_bbc_last_error
        jmp     return0
@slot_ok2:
        lda     _fnsvc_bbc_resp_buf+1
        and     #1
        ldy     #0
        sta     (ptr1),y
        lda     _fnsvc_bbc_resp_buf+2
        sta     tmp2                    ; original uri len
        clc
        adc     #4                      ; 3 + uri len + mode len byte
        cmp     tmp3
        bcc     @uri_bounds_ok
        beq     @uri_bounds_ok
        lda     #FNSVC_ERR_SHORT_RESPONSE
        sta     _fnsvc_bbc_last_error
        jmp     return0
@uri_bounds_ok:
        lda     tmp2
        cmp     #FNSVC_MOUNT_URI_MAX+1
        bcc     @uri_copy_len_ok
        lda     #FNSVC_MOUNT_URI_MAX
@uri_copy_len_ok:
        sta     tmp4                    ; capped uri copy len
        lda     #<(_fnsvc_bbc_resp_buf+3)
        sta     ptr2
        lda     #>(_fnsvc_bbc_resp_buf+3)
        sta     ptr2+1
        lda     ptr1
        clc
        adc     #1
        sta     ptr3
        lda     ptr1+1
        adc     #0
        sta     ptr3+1
        jsr     copy_tmp4
        ldy     tmp4
        lda     #0
        sta     (ptr3),y

        lda     tmp2                    ; mode offset = 3 + original uri len
        clc
        adc     #3
        tay
        lda     _fnsvc_bbc_resp_buf,y
        sta     tmp4                    ; original mode len
        iny
        tya
        clc
        adc     tmp4
        cmp     tmp3
        bcc     @mode_bounds_ok
        beq     @mode_bounds_ok
        lda     #FNSVC_ERR_SHORT_RESPONSE
        sta     _fnsvc_bbc_last_error
        jmp     return0
@mode_bounds_ok:
        tya
        clc
        adc     #<_fnsvc_bbc_resp_buf
        sta     ptr2
        lda     #0
        adc     #>_fnsvc_bbc_resp_buf
        sta     ptr2+1
        lda     ptr1
        clc
        adc     #FNSVC_MOUNT_MODE_OFF
        sta     ptr3
        lda     ptr1+1
        adc     #0
        sta     ptr3+1
        lda     tmp4
        cmp     #FNSVC_MOUNT_MODE_MAX
        bcc     @mode_copy_len_ok
        lda     #FNSVC_MOUNT_MODE_MAX-1
@mode_copy_len_ok:
        sta     tmp4
        jsr     copy_tmp4
        ldy     tmp4
        lda     #0
        sta     (ptr3),y
        jmp     return1
@bad:  jmp     return0

strnlen_uri:
        ldy     #0
@loop: lda     (ptr1),y
        beq     @ok
        iny
        cpy     #FNSVC_MOUNT_URI_MAX+1
        bne     @loop
        sec
        rts
@ok:   tya
        clc
        rts

strnlen_mode:
        ldy     #0
@loop: lda     (ptr2),y
        beq     @ok
        iny
        cpy     #4
        bne     @loop
        sec
        rts
@ok:   tya
        clc
        rts

copy_uri:
        ldy     #0
@loop: cpy     tmp3
        beq     @done
        lda     (ptr1),y
        sta     (ptr3),y
        iny
        bne     @loop
@done: rts

copy_mode:
        ldy     #0
@loop: cpy     tmp4
        beq     @done
        lda     (ptr2),y
        sta     (ptr3),y
        iny
        bne     @loop
@done: rts

copy_tmp4:
        ldy     #0
@loop: cpy     tmp4
        beq     @done
        lda     (ptr2),y
        sta     (ptr3),y
        iny
        bne     @loop
@done: rts

init_call_block:
        lda     #0
        ldx     #15
@zero: sta     call_block,x
        dex
        bpl     @zero
        lda     #FN_BBC_REASON_DEVICE_CALL
        sta     call_block
        lda     #NIO_DEVICEID_FUJI
        sta     call_block+2
        lda     #NIO_FUJI_SET_MOUNT
        sta     call_block+3
        lda     #<_fnsvc_bbc_req_buf
        sta     call_block+5
        lda     #>_fnsvc_bbc_req_buf
        sta     call_block+6
        lda     #<_fnsvc_bbc_resp_buf
        sta     call_block+9
        lda     #>_fnsvc_bbc_resp_buf
        sta     call_block+10
        lda     #<BBC_RESP_BUF_SIZE
        sta     call_block+11
        lda     #>BBC_RESP_BUF_SIZE
        sta     call_block+12
        rts

        .rodata
empty:
        .byte   0
