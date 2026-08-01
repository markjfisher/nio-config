; char *runtime_mount_display(uint8_t unit)
;
; Entry:
;   A = unit
;
; Return:
;   AX = display string pointer
;   AX = 0 on failure
;
; This implementation requests one formatted runtime-mount entry and extracts
; the final path component from:
;
;   <unit>: <RO|AUTO> <uri>\n
;
; The BBC request limits text to 240 bytes:
;
;   10-byte header + 240-byte text = 250 bytes
;
; Therefore response parsing can safely use 8-bit offsets, while still
; rejecting a nonzero entries_len high byte.

.export _runtime_mount_display

.importzp ptr1
.importzp tmp1
.importzp tmp2

.import pusha
.import pushax

.import _fn_bbc_device_call_raw
.import _fnsvc_bbc_resp_buf

.import _runtime_offsets
.import _uri_buf


.include "constants.inc"

; ---------------------------------------------------------------------------
; Protocol offsets
; ---------------------------------------------------------------------------

LIST_VERSION        = 0
LIST_FLAGS          = 1
LIST_ENTRY_COUNT_LO = 6
LIST_ENTRIES_LEN_LO = 8
LIST_ENTRIES_LEN_HI = 9
LIST_TEXT           = NIO_DISK_LIST_MOUNTS_HEADER


.segment "CODE"

_runtime_mount_display:

        ; Save the unit directly into both 16-bit request fields:
        ;
        ; first_unit = unit
        ; last_unit  = unit
        ;
        sta     mounts_request+2
        sta     mounts_request+4

        ; Clear this drive's display before querying DiskService.  A failed
        ; LIST_MOUNTS response must not leave a stale tail of a URI (the
        ; shared uri_buf is also used while assigning catalogue slots).
        tay
        lda     _runtime_offsets,y
        clc
        adc     #<_uri_buf
        sta     ptr1
        lda     #>_uri_buf
        adc     #0
        sta     ptr1+1
        ldy     #0
        lda     #0
        sta     (ptr1),y

        ; -------------------------------------------------------------------
        ; fn_bbc_device_call_raw(
        ;     NIO_DEVICE_DISK,
        ;     NIO_DISK_LIST_MOUNTS,
        ;     mounts_request,
        ;     10,
        ;     fnsvc_bbc_resp_buf,
        ;     NIO_DISK_LIST_MOUNTS_RESPONSE,
        ;     &mounts_device_status,
        ;     &mounts_response_len
        ; );
        ;
        ; Standard cc65 fastcall convention:
        ;   all arguments except the final one are pushed in source order;
        ;   the final response_len pointer is passed in AX.
        ; -------------------------------------------------------------------

        lda     #NIO_DEVICE_DISK
        jsr     pusha

        lda     #NIO_DISK_LIST_MOUNTS
        jsr     pusha

        lda     #<mounts_request
        ldx     #>mounts_request
        jsr     pushax

        lda     #10
        ldx     #0
        jsr     pushax

        lda     #<_fnsvc_bbc_resp_buf
        ldx     #>_fnsvc_bbc_resp_buf
        jsr     pushax

        lda     #<NIO_DISK_LIST_MOUNTS_RESPONSE
        ldx     #>NIO_DISK_LIST_MOUNTS_RESPONSE
        jsr     pushax

        lda     #<mounts_device_status
        ldx     #>mounts_device_status
        jsr     pushax

        lda     #<mounts_response_len
        ldx     #>mounts_response_len
        jsr     _fn_bbc_device_call_raw

        ; result != 0
        cmp     #0
        beq     call_ok
        jmp     invalid

call_ok:
        ; device_status != 0
        lda     mounts_device_status
        beq     status_ok
        jmp     invalid

status_ok:
        ; response_len must contain at least the 10-byte header.
        lda     mounts_response_len+1
        bne     header_present

        lda     mounts_response_len
        cmp     #NIO_DISK_LIST_MOUNTS_HEADER
        bcs     header_present
        jmp     invalid

header_present:
        ; Protocol version must be 1.
        lda     _fnsvc_bbc_resp_buf+LIST_VERSION
        cmp     #1
        beq     version_ok
        jmp     invalid

version_ok:
        ; Formatted-response flag, bit 1, must be set.
        lda     _fnsvc_bbc_resp_buf+LIST_FLAGS
        and     #$02
        bne     formatted_ok
        jmp     invalid

formatted_ok:
        ; There must be at least one entry.
        ;
        ; This matches the original C check of response[6].
        lda     _fnsvc_bbc_resp_buf+LIST_ENTRY_COUNT_LO
        bne     entry_present
        jmp     invalid

entry_present:
        ; The protocol length is 16-bit, but this caller requested a maximum
        ; of 240 bytes. Reject a response that cannot be represented by our
        ; byte-offset parser.
        lda     _fnsvc_bbc_resp_buf+LIST_ENTRIES_LEN_HI
        beq     length_high_ok
        jmp     invalid

length_high_ok:
        lda     _fnsvc_bbc_resp_buf+LIST_ENTRIES_LEN_LO

        ; Original C requires at least eight bytes of formatted text.
        cmp     #8
        bcs     length_minimum_ok
        jmp     invalid

length_minimum_ok:
        ; Reject anything beyond the requested 240-byte budget.
        cmp     #BBC_MOUNTS_PAYLOAD+1
        bcc     length_within_budget
        jmp     invalid

length_within_budget:
        ; tmp1 = exclusive end offset:
        ;
        ;   NIO_DISK_LIST_MOUNTS_HEADER + entries_len
        ;
        clc
        adc     #NIO_DISK_LIST_MOUNTS_HEADER
        bcc     end_offset_ok
        jmp     invalid

end_offset_ok:
        sta     tmp1

        ; Verify that the received response actually contains the complete
        ; declared text.
        lda     mounts_response_len+1
        bne     response_complete

        lda     mounts_response_len
        cmp     tmp1
        bcs     response_complete
        jmp     invalid

response_complete:
        ; -------------------------------------------------------------------
        ; Validate:
        ;
        ;   start[0] == '0' + unit
        ;   start[1] == ':'
        ;   start[2] == ' '
        ; -------------------------------------------------------------------

        lda     mounts_request+2
        clc
        adc     #'0'
        cmp     _fnsvc_bbc_resp_buf+LIST_TEXT
        beq     unit_ok
        jmp     invalid

unit_ok:
        lda     _fnsvc_bbc_resp_buf+LIST_TEXT+1
        cmp     #':'
        beq     colon_ok
        jmp     invalid

colon_ok:
        lda     _fnsvc_bbc_resp_buf+LIST_TEXT+2
        cmp     #' '
        beq     prefix_ok
        jmp     invalid

prefix_ok:
        ; -------------------------------------------------------------------
        ; Calculate:
        ;
        ;   display = &uri_buf[runtime_offsets[unit]]
        ;
        ; runtime_offsets is a uint8_t[] of offsets within uri_buf.
        ; -------------------------------------------------------------------

        lda     mounts_request+2
        tay

        lda     _runtime_offsets,y
        clc
        adc     #<_uri_buf
        sta     ptr1

        lda     #>_uri_buf
        adc     #0
        sta     ptr1+1

        ; Begin immediately after "<unit>: ".
        ldx     #LIST_TEXT+3


; ---------------------------------------------------------------------------
; Skip the access mode: "RO" or "AUTO"
; ---------------------------------------------------------------------------

find_mode_space:
        cpx     tmp1
        bcc     mode_byte_available
        jmp     invalid

mode_byte_available:
        lda     _fnsvc_bbc_resp_buf,x
        inx
        cmp     #' '
        bne     find_mode_space


; ---------------------------------------------------------------------------
; Skip spaces between access mode and URI
; ---------------------------------------------------------------------------

skip_spaces:
        cpx     tmp1
        bcc     space_byte_available
        jmp     invalid

space_byte_available:
        lda     _fnsvc_bbc_resp_buf,x
        cmp     #' '
        bne     uri_found

        inx
        bne     skip_spaces             ; X cannot wrap in a valid response

uri_found:
        ; tmp2 holds the current basename candidate.
        ;
        ; Initially this is the start of the complete URI.
        stx     tmp2


; ---------------------------------------------------------------------------
; Scan the URI.
;
; Every '/' or ':' moves the candidate basename to the byte following that
; separator.
; ---------------------------------------------------------------------------

scan_uri:
        cpx     tmp1
        bcs     name_end_found

        lda     _fnsvc_bbc_resp_buf,x

        ; Formatted records are newline terminated. Stop before the newline,
        ; rather than including it in the display string.
        cmp     #$0A
        beq     name_end_found

        inx

        cmp     #'/'
        beq     new_name_start

        cmp     #':'
        bne     scan_uri

new_name_start:
        stx     tmp2
        jmp     scan_uri


; ---------------------------------------------------------------------------
; Copy at most BBC_RUNTIME_NAME_WIDTH bytes.
;
; At entry:
;   X    = exclusive end of the filename, or newline offset
;   tmp2 = basename start
;   ptr1 = display destination
; ---------------------------------------------------------------------------

name_end_found:
        stx     tmp1                    ; tmp1 now becomes copy-end offset
        ldx     tmp2
        ldy     #0

copy_name:
        cpx     tmp1
        bcs     terminate

        cpy     #BBC_RUNTIME_NAME_WIDTH
        bcs     terminate

        lda     _fnsvc_bbc_resp_buf,x
        sta     (ptr1),y

        inx
        iny
        bne     copy_name               ; width is necessarily below 256

terminate:
        lda     #0
        sta     (ptr1),y

        ; Return display in AX.
        lda     ptr1
        ldx     ptr1+1
        rts


invalid:
        lda     #0
        tax
        rts


; ---------------------------------------------------------------------------
; Fixed request and call-result storage
;
; LIST_MOUNTS request:
;
;   u8  version             = 1
;   u8  flags               = 1, formatted
;   u16 first_unit          = patched at runtime
;   u16 last_unit           = patched at runtime
;   u16 start_index         = 0
;   u16 max_payload_bytes   = BBC_MOUNTS_PAYLOAD
; ---------------------------------------------------------------------------

.segment "DATA"

mounts_request:
        .byte   1
        .byte   1
        .word   0                       ; first_unit
        .word   0                       ; last_unit
        .word   0                       ; start_index
        .word   BBC_MOUNTS_PAYLOAD


.segment "BSS"

mounts_device_status:
        .res    1

mounts_response_len:
        .res    2
