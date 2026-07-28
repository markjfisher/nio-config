        .export _fnsvc_config_nio_list_directory_page

        .import popa, popax
        .import _fn_bbc_osword78, _fn_bbc_status_to_result
.ifdef CONFIG_NIO_BBC_XRAM_TABLES
        .import _config_nio_xram_begin, _config_nio_xram_end
.else
        .import _config_nio_bbc_entries
.endif
        .import _fnsvc_bbc_req_buf, _fnsvc_bbc_resp_buf
        .import _fnsvc_bbc_last_error, _fnsvc_bbc_last_status
        .import _fnsvc_bbc_last_raw_error
        .import _fnsvc_bbc_last_response_len
        .importzp ptr1, ptr2, ptr3, tmp1, tmp2, tmp3, tmp4

FN_BBC_STATUS_OK        = $00
FN_BBC_REASON_DEVICE_CALL = $06
NIO_DEVICEID_FILE       = $FE
NIO_FILE_LIST_DIRECTORY = $02
NIO_FILE_VERSION        = $01
NIO_FILE_LIST_FLAGS     = $03
NIO_FILE_LIST_RESP_MORE = $01
NIO_FILE_LIST_ENTRY_TRUNCATED = $80
BBC_REQ_BUF_SIZE        = 170
.ifndef FNSVC_LIST_MAX_PAYLOAD
FNSVC_LIST_MAX_PAYLOAD  = 120
.endif
BBC_LIST_PAYLOAD        = FNSVC_LIST_MAX_PAYLOAD
BBC_RESP_BUF_SIZE       = BBC_LIST_PAYLOAD + 10
FNSVC_ERR_NONE          = 0
FNSVC_ERR_INVALID_ARG   = 1
FNSVC_ERR_REQUEST_TOO_LARGE = 2
FNSVC_ERR_TRANSPORT     = 3
FNSVC_ERR_STATUS        = 4
FNSVC_ERR_BAD_VERSION   = 5
FNSVC_ERR_SHORT_RESPONSE = 6
FNSVC_ERR_ENTRIES_BOUNDS = 7
FNSVC_ERR_ENTRY_BOUNDS  = 8

XRAM_BANK       = 7
ENTRY_BASE_LO   = $58
ENTRY_BASE_HI   = $8C
ENTRY_SIZE      = $20
ENTRY_NAME_MAX  = 30

STATE_ENTRY_COUNT = 2

        .bss
call_block:
        .res    16
state_ptr:
        .res    2
next_ptr:
        .res    2
more_ptr:
        .res    2
start_lo:
        .res    1
start_hi:
        .res    1
max_entries:
        .res    1
base_count:
        .res    1
resp_len_lo:
        .res    1
resp_len_hi:
        .res    1
resp_flags:
        .res    1
count_lo:
        .res    1
delivered:
        .res    1
saw_undelivered:
        .res    1
entry_name_len:
        .res    1
entry_copy_len:
        .res    1

        .code

begin_entries:
.ifdef CONFIG_NIO_BBC_XRAM_TABLES
        lda     #XRAM_BANK
        jmp     _config_nio_xram_begin
.else
        rts
.endif

end_entries:
.ifdef CONFIG_NIO_BBC_XRAM_TABLES
        jmp     _config_nio_xram_end
.else
        rts
.endif

list_return0:
        lda     #0
        tax
        rts

list_return1:
        lda     #1
        ldx     #0
        rts

fail_a:
        sta     _fnsvc_bbc_last_error
        jmp     list_return0

; int fnsvc_config_nio_list_directory_page(config_nio_state_t *state,
;   const char *uri, uint16_t start, uint8_t max_entries,
;   uint16_t *next_start, uint8_t *more)
_fnsvc_config_nio_list_directory_page:
        sta     more_ptr
        stx     more_ptr+1
        jsr     popax                   ; next_start
        sta     next_ptr
        stx     next_ptr+1
        jsr     popa                    ; max_entries
        sta     max_entries
        jsr     popax                   ; start
        sta     start_lo
        stx     start_hi
        jsr     popax                   ; uri
        sta     ptr1
        stx     ptr1+1
        jsr     popax                   ; state
        sta     state_ptr
        stx     state_ptr+1

        lda     state_ptr
        ora     state_ptr+1
        bne     @state_ok
        jmp     @bad_arg
@state_ok:
        lda     ptr1
        ora     ptr1+1
        bne     @uri_ok
        jmp     @bad_arg
@uri_ok:
        lda     max_entries
        bne     @args_ok
        jmp     @bad_arg
@args_ok:

        lda     #0
        ldx     state_ptr
        stx     ptr3
        ldx     state_ptr+1
        stx     ptr3+1
        sta     _fnsvc_bbc_last_error
        sta     _fnsvc_bbc_last_status
        sta     _fnsvc_bbc_last_raw_error
        sta     _fnsvc_bbc_last_response_len
        sta     _fnsvc_bbc_last_response_len+1
        ldy     #STATE_ENTRY_COUNT
        lda     (ptr3),y
        sta     base_count

        ldy     #0
@strlen:
        lda     (ptr1),y
        beq     @len_ok
        iny
        cpy     #129
        bne     @strlen
        lda     #FNSVC_ERR_REQUEST_TOO_LARGE
        jmp     fail_a
@len_ok:
        sty     tmp1                    ; uri length
        cpy     #163                    ; 170 - fixed 7 bytes
        bcc     @req_ok
        lda     #FNSVC_ERR_REQUEST_TOO_LARGE
        jmp     fail_a
@req_ok:
        lda     #NIO_FILE_VERSION
        sta     _fnsvc_bbc_req_buf
        lda     tmp1
        sta     _fnsvc_bbc_req_buf+1
        lda     #0
        sta     _fnsvc_bbc_req_buf+2

        lda     #<(_fnsvc_bbc_req_buf+3)
        sta     ptr2
        lda     #>(_fnsvc_bbc_req_buf+3)
        sta     ptr2+1
        ldy     #0
@copy_uri:
        cpy     tmp1
        beq     @uri_done
        lda     (ptr1),y
        sta     (ptr2),y
        iny
        bne     @copy_uri
@uri_done:
        tya
        clc
        adc     #3
        tay
        lda     start_lo
        sta     _fnsvc_bbc_req_buf,y
        iny
        lda     start_hi
        sta     _fnsvc_bbc_req_buf,y
        iny
        lda     #<BBC_LIST_PAYLOAD
        sta     _fnsvc_bbc_req_buf,y
        iny
        lda     #>BBC_LIST_PAYLOAD
        sta     _fnsvc_bbc_req_buf,y
        iny
        lda     #NIO_FILE_LIST_FLAGS
        sta     _fnsvc_bbc_req_buf,y
        iny
        lda     #ENTRY_NAME_MAX
        sta     _fnsvc_bbc_req_buf,y
        iny
        sty     tmp2                    ; request length

        jsr     init_call_block
        lda     tmp2
        sta     call_block+7

        lda     #<call_block
        ldx     #>call_block
        jsr     _fn_bbc_osword78
        cmp     #FN_BBC_STATUS_OK
        beq     @rom_ok
        jsr     _fn_bbc_status_to_result
        sta     _fnsvc_bbc_last_raw_error
        lda     #FNSVC_ERR_TRANSPORT
        jmp     fail_a

@rom_ok:
        lda     #0
        sta     _fnsvc_bbc_last_raw_error
        lda     call_block+4
        sta     _fnsvc_bbc_last_status
        lda     call_block+13
        sta     _fnsvc_bbc_last_response_len
        sta     resp_len_lo
        lda     call_block+14
        sta     _fnsvc_bbc_last_response_len+1
        sta     resp_len_hi
@status_check:
        lda     _fnsvc_bbc_last_status
        beq     @status_ok
        lda     #FNSVC_ERR_STATUS
        jmp     fail_a
@status_ok:
        lda     resp_len_hi
        bne     @len_min_ok
        lda     resp_len_lo
        cmp     #10
        bcs     @len_min_ok
        lda     #FNSVC_ERR_SHORT_RESPONSE
        jmp     fail_a
@len_min_ok:
        lda     _fnsvc_bbc_resp_buf
        cmp     #NIO_FILE_VERSION
        beq     @version_ok
        lda     #FNSVC_ERR_BAD_VERSION
        jmp     fail_a
@version_ok:
        lda     _fnsvc_bbc_resp_buf+1
        sta     resp_flags
        lda     _fnsvc_bbc_resp_buf+7
        beq     @count_ok
        lda     #$FF
        bne     @store_count
@count_ok:
        lda     _fnsvc_bbc_resp_buf+6
@store_count:
        sta     count_lo
        lda     _fnsvc_bbc_resp_buf+8
        clc
        adc     #10
        sta     tmp2
        lda     _fnsvc_bbc_resp_buf+9
        adc     #0
        sta     tmp4
        lda     tmp4
        cmp     #>BBC_RESP_BUF_SIZE
        bcc     @required_fits
        bne     @entries_bad
        lda     tmp2
        cmp     #<BBC_RESP_BUF_SIZE+1
        bcs     @entries_bad
@required_fits:
        lda     tmp4
        cmp     resp_len_hi
        bcc     @entries_ok
        bne     @use_required_len
        lda     tmp2
        cmp     resp_len_lo
        bcc     @entries_ok
        beq     @entries_ok
@use_required_len:
        lda     tmp2
        sta     resp_len_lo
        lda     tmp4
        sta     resp_len_hi
        jmp     @entries_ok
@entries_bad:
        lda     #FNSVC_ERR_ENTRIES_BOUNDS
        jmp     fail_a

@entries_ok:
        lda     #<(_fnsvc_bbc_resp_buf+10)
        sta     ptr1                    ; response entry cursor
        lda     #>(_fnsvc_bbc_resp_buf+10)
        sta     ptr1+1
.ifdef CONFIG_NIO_BBC_XRAM_TABLES
        lda     #ENTRY_BASE_LO
        sta     ptr2                    ; XRAM entry cursor
        lda     #ENTRY_BASE_HI
        sta     ptr2+1
.else
        lda     #<_config_nio_bbc_entries
        sta     ptr2                    ; entry cursor
        lda     #>_config_nio_bbc_entries
        sta     ptr2+1
.endif
        ldx     base_count
        beq     @entry_base_ready
@advance_base:
        jsr     advance_entry_ptr
        dex
        bne     @advance_base
@entry_base_ready:
        lda     #0
        sta     delivered
        sta     saw_undelivered

        jsr     begin_entries

@entry_loop:
        lda     count_lo
        beq     @parse_done
        jsr     ensure_two
        bcs     @entry_bounds
        ldy     #0
        lda     (ptr1),y                ; eflags
        and     #(1 | NIO_FILE_LIST_ENTRY_TRUNCATED)
        sta     tmp3
        iny
        lda     (ptr1),y                ; name_len
        sta     entry_name_len
        jsr     advance_ptr1_two
        jsr     ensure_name
        bcs     @entry_bounds

        lda     delivered
        cmp     max_entries
        bcc     @store_entry
        lda     #1
        sta     saw_undelivered
        bne     @skip_store
@store_entry:
        ldy     #0
        lda     tmp3
        sta     (ptr2),y
        lda     entry_name_len
        cmp     #ENTRY_NAME_MAX+1
        bcc     @copy_len_ok
        lda     #ENTRY_NAME_MAX
@copy_len_ok:
        sta     entry_copy_len
        tay
        lda     #0
        iny
        sta     (ptr2),y                ; terminator
        ldy     #0
@copy_name:
        cpy     entry_copy_len
        beq     @store_done
        lda     (ptr1),y
        iny
        sta     (ptr2),y
        bne     @copy_name
@store_done:
        inc     delivered
        jsr     advance_entry_ptr

@skip_store:
        jsr     advance_ptr1_name
        dec     count_lo
        jmp     @entry_loop

@entry_bounds:
        jsr     end_entries
        lda     #FNSVC_ERR_ENTRY_BOUNDS
        jmp     fail_a

@parse_done:
        jsr     end_entries
        ldy     #STATE_ENTRY_COUNT
        lda     base_count
        clc
        adc     delivered
        ldx     state_ptr
        stx     ptr3
        ldx     state_ptr+1
        stx     ptr3+1
        sta     (ptr3),y
        lda     next_ptr
        ora     next_ptr+1
        beq     @skip_next
        lda     start_lo
        clc
        adc     delivered
        ldy     #0
        ldx     next_ptr
        stx     ptr3
        ldx     next_ptr+1
        stx     ptr3+1
        sta     (ptr3),y
        lda     start_hi
        adc     #0
        iny
        sta     (ptr3),y
@skip_next:
        lda     more_ptr
        ora     more_ptr+1
        beq     @done_more
        lda     #0
        ldx     saw_undelivered
        bne     @set_more
        lda     resp_flags
        and     #NIO_FILE_LIST_RESP_MORE
        beq     @write_more
@set_more:
        lda     #1
@write_more:
        ldy     #0
        ldx     more_ptr
        stx     ptr3
        ldx     more_ptr+1
        stx     ptr3+1
        sta     (ptr3),y
@done_more:
        jmp     list_return1

@bad_arg:
        lda     #FNSVC_ERR_INVALID_ARG
        jmp     fail_a

ensure_two:
        lda     ptr1
        sec
        sbc     #<_fnsvc_bbc_resp_buf
        sta     tmp2
        lda     ptr1+1
        sbc     #>_fnsvc_bbc_resp_buf
        sta     tmp4
        lda     tmp2
        clc
        adc     #2
        sta     tmp2
        lda     tmp4
        adc     #0
        sta     tmp4
        jmp     check_response_bound

ensure_name:
        lda     ptr1
        sec
        sbc     #<_fnsvc_bbc_resp_buf
        sta     tmp2
        lda     ptr1+1
        sbc     #>_fnsvc_bbc_resp_buf
        sta     tmp4
        lda     tmp2
        clc
        adc     entry_name_len
        sta     tmp2
        lda     tmp4
        adc     #0
        sta     tmp4
        ; fall through

check_response_bound:
        lda     tmp4
        cmp     resp_len_hi
        bcc     @ok
        bne     @bad
        lda     tmp2
        cmp     resp_len_lo
        bcc     @ok
        beq     @ok
@bad:  sec
        rts
@ok:   clc
        rts

advance_ptr1_two:
        lda     ptr1
        clc
        adc     #2
        sta     ptr1
        bcc     @done
        inc     ptr1+1
@done: rts

advance_ptr1_name:
        lda     ptr1
        clc
        adc     entry_name_len
        sta     ptr1
        bcc     @done
        inc     ptr1+1
@done: rts

advance_entry_ptr:
        lda     ptr2
        clc
        adc     #ENTRY_SIZE
        sta     ptr2
        bcc     @done
        inc     ptr2+1
@done: rts

init_call_block:
        lda     #0
        ldx     #15
@zero: sta     call_block,x
        dex
        bpl     @zero
        lda     #FN_BBC_REASON_DEVICE_CALL
        sta     call_block
        lda     #NIO_DEVICEID_FILE
        sta     call_block+2
        lda     #NIO_FILE_LIST_DIRECTORY
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
