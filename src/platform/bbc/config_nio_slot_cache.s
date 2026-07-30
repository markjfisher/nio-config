        .export _config_nio_bbc_invalidate_slot_cache
        .export _config_nio_refresh_slots

        .import _config_nio_appstore_buf
        .import _config_nio_store_buf
        .import _config_nio_read_slot_page
        .import _config_nio_read_slot_page_previous
.ifdef CONFIG_NIO_BBC_XRAM_TABLES
        .import _config_nio_bbc_slot_get
        .import _config_nio_bbc_slot_set
        .import pusha
.else
        .import _config_nio_bbc_slots
        .import _fnsvc_bbc_resp_buf
.endif
        .importzp ptr1

PAGE_SIZE = 8
STATE_SLOT_START = 1
STATE_SLOT_COUNT = 2
STATE_SLOTS_MORE = 3

        .bss
active_start:       .res 1
previous_start:     .res 1
active_valid:       .res 1
previous_valid:     .res 1
state_ptr:          .res 2
row_index:          .res 1
requested_start:    .res 1

        .code

return0:
        lda     #0
        tax
        rts

return1:
        lda     #1
        ldx     #0
        rts

restore_state_ptr:
        lda     state_ptr
        sta     ptr1
        lda     state_ptr+1
        sta     ptr1+1
        rts

_config_nio_bbc_invalidate_slot_cache:
        lda     #0
        sta     active_valid
        sta     previous_valid
        rts

.ifdef CONFIG_NIO_BBC_XRAM_TABLES
get_slot_appbuf:
        jsr     pusha
        lda     #<_config_nio_appstore_buf
        ldx     #>_config_nio_appstore_buf
        jmp     _config_nio_bbc_slot_get

set_slot_appbuf:
        jsr     pusha
        lda     #<_config_nio_appstore_buf
        ldx     #>_config_nio_appstore_buf
        jmp     _config_nio_bbc_slot_set

get_slot_storebuf:
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jmp     _config_nio_bbc_slot_get

set_slot_storebuf:
        jsr     pusha
        lda     #<_config_nio_store_buf
        ldx     #>_config_nio_store_buf
        jmp     _config_nio_bbc_slot_set
.endif

swap_pages:
.ifdef CONFIG_NIO_BBC_XRAM_TABLES
        lda     #0
        sta     row_index
@loop:  lda     row_index
        jsr     get_slot_appbuf
        lda     row_index
        clc
        adc     #PAGE_SIZE
        jsr     get_slot_storebuf
        lda     row_index
        jsr     set_slot_storebuf
        lda     row_index
        clc
        adc     #PAGE_SIZE
        jsr     set_slot_appbuf
        inc     row_index
        lda     row_index
        cmp     #PAGE_SIZE
        bne     @loop
.else
        ldx     #0
@loop:  lda     _config_nio_bbc_slots,x
        tay
        lda     _fnsvc_bbc_resp_buf,x
        sta     _config_nio_bbc_slots,x
        tya
        sta     _fnsvc_bbc_resp_buf,x
        inx
        cpx     #PAGE_SIZE*30
        bne     @loop
.endif
        lda     active_start
        ldx     previous_start
        stx     active_start
        sta     previous_start
        rts

; int config_nio_refresh_slots(config_nio_state_t *state)
_config_nio_refresh_slots:
        sta     state_ptr
        stx     state_ptr+1
        ora     state_ptr+1
        bne     :+
        jmp     return0
:
        jsr     restore_state_ptr
        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        sta     requested_start
        lda     active_valid
        beq     @not_active
        lda     active_start
        cmp     requested_start
        beq     @count
@not_active:
        lda     previous_valid
        beq     @fetch
        lda     previous_start
        cmp     requested_start
        bne     @fetch
        jsr     swap_pages
        lda     #1
        sta     active_valid
        jmp     @count

@fetch:
        lda     active_valid
        beq     @read_active
        lda     requested_start
        sta     previous_start
        jsr     _config_nio_read_slot_page_previous
        cmp     #1
        bne     @previous_failed
        jsr     swap_pages
        lda     #1
        sta     previous_valid
        sta     active_valid
        jmp     @count

@read_active:
        lda     requested_start
        jsr     _config_nio_read_slot_page
        cmp     #1
        beq     @read_ok
        lda     #0
        sta     active_valid
        jmp     return0
@previous_failed:
        lda     #0
        sta     previous_valid
        jmp     return0
@read_ok:
        lda     requested_start
        sta     active_start
        lda     #1
        sta     active_valid

@count:
.ifdef CONFIG_NIO_BBC_XRAM_TABLES
        lda     #0
        sta     row_index
        sta     _config_nio_store_buf
@count_loop:
        lda     row_index
        jsr     get_slot_appbuf
        lda     _config_nio_appstore_buf
        beq     :+
        inc     _config_nio_store_buf
:
        inc     row_index
        lda     row_index
        cmp     #PAGE_SIZE
        bne     @count_loop
.else
        lda     #0
        sta     _config_nio_store_buf
        ldx     #0
@count_loop:
        lda     _config_nio_bbc_slots,x
        beq     :+
        inc     _config_nio_store_buf
:
        txa
        clc
        adc     #30
        tax
        cmp     #PAGE_SIZE*30
        bne     @count_loop
.endif
        jsr     restore_state_ptr
        ldy     #STATE_SLOT_COUNT
        lda     _config_nio_store_buf
        sta     (ptr1),y
        iny
        lda     #0
        sta     (ptr1),y
        ldy     #STATE_SLOT_START
        lda     (ptr1),y
        cmp     #248
        bcs     :+
        ldy     #STATE_SLOTS_MORE
        lda     #1
        sta     (ptr1),y
:
        jmp     return1
