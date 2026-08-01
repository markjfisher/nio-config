        .export _config_nio_read_slot
        .export _config_nio_read_slot_page
        .export _config_nio_read_slot_page_previous
        .export _config_nio_bbc_put_slot
        .export _config_nio_bbc_delete_slot

        .import _config_nio_appstore_buf
        .import _config_nio_store_buf
        .import _config_nio_bbc_slot_index
        .import _config_nio_bbc_slot_flags
        .import _config_nio_bbc_slot_uri
        .import _config_nio_bbc_slot_set
        .import _fn_slot_catalog_call
        .import popa, pusha, pushax
        .import return0, return1
        .importzp ptr1, ptr2, tmp1, tmp2, tmp3, tmp4

SLOT_CATALOG_CMD_RANGE      = $04
SLOT_CATALOG_CMD_PUT        = $02
SLOT_CATALOG_CMD_DELETE     = $03
SLOT_TAIL_URI               = $01
SLOT_MORE                   = $01
SLOT_ENTRY_VALID            = $01
STORE_SIZE                  = 133
MAX_PAYLOAD                 = STORE_SIZE - 7
SLOT_SIZE                   = 30
SLOT_URI_MAX                = 28
PAGE_SIZE                   = 8

        .data
catalog_io:
        .addr   _config_nio_store_buf
        .word   STORE_SIZE

        .bss
response_len:   .res 2
lower_index:    .res 1
upper_index:    .res 1
cursor_index:   .res 1
entry_index:    .res 1
entry_flags:    .res 1
entry_len:      .res 1
entry_count:    .res 1
dest_ptr:       .res 2
end_ptr:        .res 2
next_ptr:       .res 2
table_base:     .res 1
mutation_command: .res 1
mutation_request_len: .res 1

        .code

; Complete a Slot Catalog call and accept only a successful response whose
; first byte is the protocol version. Command is in A, request length in X.
catalog_mutation_call:
        sta     mutation_command
        stx     mutation_request_len
        lda     #<catalog_io
        ldx     #>catalog_io
        jsr     pushax
        lda     mutation_command
        jsr     pusha
        lda     mutation_request_len
        ldx     #0
        jsr     pushax
        lda     #<response_len
        ldx     #>response_len
        jsr     _fn_slot_catalog_call
        bne     @bad
        lda     response_len+1
        bne     @bad
        lda     response_len
        beq     @bad
        lda     _config_nio_store_buf
        cmp     #1
        bne     @bad
        jmp     return1
@bad:   jmp     return0

; Assemble Put without pulling the generic C string/copy implementation into
; the memory-constrained BBC transient application.
_config_nio_bbc_put_slot:
        lda     _config_nio_bbc_slot_uri
        sta     ptr1
        lda     _config_nio_bbc_slot_uri+1
        sta     ptr1+1
        ldy     #0
@length:
        lda     (ptr1),y
        beq     @have_length
        iny
        cpy     #129
        bcc     @length
        jmp     return0
@have_length:
        tya
        beq     @invalid
        sta     tmp3
        lda     #1
        sta     _config_nio_store_buf
        lda     _config_nio_bbc_slot_index
        sta     _config_nio_store_buf+1
        lda     _config_nio_bbc_slot_flags
        sta     _config_nio_store_buf+2
        lda     tmp3
        sta     _config_nio_store_buf+3
        lda     #0
        sta     _config_nio_store_buf+4
        ldy     #0
@copy:
        lda     (ptr1),y
        sta     _config_nio_store_buf+5,y
        iny
        cpy     tmp3
        bne     @copy
        tya
        clc
        adc     #5
        tax
        lda     #SLOT_CATALOG_CMD_PUT
        jmp     catalog_mutation_call
@invalid:
        jmp     return0

_config_nio_bbc_delete_slot:
        lda     #1
        sta     _config_nio_store_buf
        lda     _config_nio_bbc_slot_index
        sta     _config_nio_store_buf+1
        ldx     #2
        lda     #SLOT_CATALOG_CMD_DELETE
        jmp     catalog_mutation_call

clear_slot_temp:
        lda     #0
        ldx     #SLOT_SIZE-1
@loop:  sta     _config_nio_appstore_buf,x
        dex
        bpl     @loop
        rts

; Build and issue a range request from lower_index/upper_index/cursor_index.
; All parse state lives in globals because the call into C may change ptr/tmp.
catalog_call:
        lda     #1
        sta     _config_nio_store_buf
        lda     lower_index
        sta     _config_nio_store_buf+1
        lda     upper_index
        sta     _config_nio_store_buf+2
        lda     cursor_index
        sta     _config_nio_store_buf+3
        lda     #SLOT_TAIL_URI
        sta     _config_nio_store_buf+4
        lda     #SLOT_URI_MAX
        sta     _config_nio_store_buf+5
        lda     #<MAX_PAYLOAD
        sta     _config_nio_store_buf+6
        lda     #>MAX_PAYLOAD
        sta     _config_nio_store_buf+7

        ; cc65 passes arguments right-to-left: the rightmost response_len
        ; pointer is in A/X, while io, command, and request_len are stacked
        ; left-to-right below it.
        lda     #<catalog_io
        ldx     #>catalog_io
        jsr     pushax
        lda     #SLOT_CATALOG_CMD_RANGE
        jsr     pusha
        lda     #8
        ldx     #0
        jsr     pushax
        lda     #<response_len
        ldx     #>response_len
        jsr     _fn_slot_catalog_call
        bne     @bad
        lda     response_len+1
        bne     @bad
        lda     response_len
        cmp     #7
        bcc     @bad
        lda     _config_nio_store_buf
        cmp     #1
        bne     @bad
        jmp     return1
@bad:  jmp     return0

; ptr1 = first entry, end_ptr = byte after last entry, entry_count set.
prepare_entries:
        clc
        lda     #<(_config_nio_store_buf+7)
        adc     _config_nio_store_buf+3
        sta     ptr1
        lda     #>(_config_nio_store_buf+7)
        adc     #0
        sta     ptr1+1
        clc
        lda     ptr1
        adc     _config_nio_store_buf+5
        sta     end_ptr
        lda     ptr1+1
        adc     _config_nio_store_buf+6
        sta     end_ptr+1
        lda     _config_nio_store_buf+4
        sta     entry_count
        rts

; Parse one record at ptr1 and advance ptr1. Carry set means malformed.
next_entry:
        lda     ptr1+1
        cmp     end_ptr+1
        bne     @header_ok
        lda     ptr1
        clc
        adc     #3
        cmp     end_ptr
        bcc     @header_ok
        beq     @header_ok
        sec
        rts
@header_ok:
        ldy     #0
        lda     (ptr1),y
        sta     entry_index
        iny
        lda     (ptr1),y
        sta     entry_flags
        iny
        lda     (ptr1),y
        sta     entry_len
        clc
        lda     ptr1
        adc     #3
        sta     ptr1
        bcc     :+
        inc     ptr1+1
:
        clc
        lda     ptr1
        adc     entry_len
        sta     tmp1
        lda     ptr1+1
        adc     #0
        sta     next_ptr+1
        lda     tmp1
        sta     next_ptr
        lda     next_ptr+1
        cmp     end_ptr+1
        bcc     @valid
        bne     @bad
        lda     next_ptr
        cmp     end_ptr
        bcc     @valid
        beq     @valid
@bad:  sec
        rts
@valid:
        clc
        rts

; int config_nio_read_slot(uint8_t index, config_nio_slot_t *slot)
; The rightmost pointer arrives in A/X; the index is on the C stack.
_config_nio_read_slot:
        sta     dest_ptr
        stx     dest_ptr+1
        sta     ptr2
        stx     ptr2+1
        jsr     popa
        sta     lower_index
        sta     upper_index
        sta     cursor_index
        ldy     #SLOT_SIZE-1
        lda     #0
@clear: sta     (ptr2),y
        dey
        bpl     @clear
        jsr     catalog_call
        cmp     #1
        beq     :+
        jmp     @bad
:
        lda     dest_ptr
        sta     ptr2
        lda     dest_ptr+1
        sta     ptr2+1
        lda     _config_nio_store_buf+4
        beq     @empty
        jsr     prepare_entries
        jsr     next_entry
        bcs     @bad
        lda     entry_index
        cmp     lower_index
        bne     @bad
        lda     entry_flags
        and     #SLOT_ENTRY_VALID
        beq     @bad
        lda     entry_len
        beq     @bad
        cmp     #SLOT_URI_MAX+1
        bcs     @bad
        ldy     #0
        lda     #1
        sta     (ptr2),y
@copy:  lda     (ptr1),y
        iny
        sta     (ptr2),y
        cpy     entry_len
        bne     @copy
        lda     #0
        iny
        sta     (ptr2),y
@empty: jmp     return1
@bad:   jmp     return0

; int config_nio_read_slot_page(uint8_t start)
_config_nio_read_slot_page:
        ldx     #0
        stx     table_base
        jmp     read_slot_page

; Fetch into the spare eight-row table used by the two-page cache.
_config_nio_read_slot_page_previous:
        ldx     #PAGE_SIZE
        stx     table_base
read_slot_page:
        sta     lower_index
        sta     cursor_index
        clc
        adc     #PAGE_SIZE-1
        sta     upper_index
        jsr     clear_slot_temp
        lda     #0
        sta     entry_index
@clear_rows:
        lda     entry_index
        clc
        adc     table_base
        jsr     pusha
        lda     #<_config_nio_appstore_buf
        ldx     #>_config_nio_appstore_buf
        jsr     _config_nio_bbc_slot_set
        inc     entry_index
        lda     entry_index
        cmp     #PAGE_SIZE
        bne     @clear_rows

@request:
        jsr     catalog_call
        cmp     #1
        beq     :+
        jmp     @bad
:
        jsr     prepare_entries
@entry_loop:
        lda     entry_count
        beq     @page_done
        jsr     next_entry
        bcs     @bad
        lda     entry_index
        cmp     lower_index
        bcc     @bad
        cmp     upper_index
        beq     @index_ok
        bcs     @bad
@index_ok:
        jsr     clear_slot_temp
        lda     entry_flags
        and     #SLOT_ENTRY_VALID
        beq     @store
        lda     entry_len
        beq     @store
        cmp     #SLOT_URI_MAX+1
        bcs     @store
        lda     #1
        sta     _config_nio_appstore_buf
        ldy     #0
@copy_uri:
        lda     (ptr1),y
        iny
        sta     _config_nio_appstore_buf,y
        cpy     entry_len
        bne     @copy_uri
@store:
        lda     entry_index
        sec
        sbc     lower_index
        clc
        adc     table_base
        jsr     pusha
        lda     #<_config_nio_appstore_buf
        ldx     #>_config_nio_appstore_buf
        jsr     _config_nio_bbc_slot_set
        lda     next_ptr
        sta     ptr1
        lda     next_ptr+1
        sta     ptr1+1
        dec     entry_count
        jmp     @entry_loop

@page_done:
        lda     _config_nio_store_buf+1
        and     #SLOT_MORE
        beq     @ok
        lda     _config_nio_store_buf+2
        cmp     cursor_index
        beq     @bad
        bcc     @bad
        sta     cursor_index
        jmp     @request
@ok:    jmp     return1
@bad:   jmp     return0
