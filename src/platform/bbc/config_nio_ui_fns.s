        .export   _label_width

        .import   _clear_field
        .import   _current_screen
        .import   _hosts_start
        .import   _selected_host

        .import   addysp
        .import   decsp2
        .import   decsp5
        .import   popax
        .import   pusha
        .import   return0
        .importzp ptr1
        .importzp ptr2
        .importzp ptr3
        .importzp tmp1
        .importzp tmp2
        .importzp c_sp

        .include  "config_nio_layout.inc"

SCREEN_HOSTS   := 0
SCREEN_BROWSE  := 1
SCREEN_SLOTS   := 2

BBC_HOST_TEXT_X := CONFIG_NIO_BBC_HOSTS_ROWS_X + 4


        .code

; unsigned char __near__ label_width (const char *label)
; original C implementation 63 bytes, this is 24 without X set
_label_width:
        sta     ptr1
        stx     ptr1+1
        ora     ptr1+1                  ; check if label is null
        bne     have_label
        jmp     return0

have_label:
        ldy     #$00
@len_loop:
        lda     (ptr1), y
        beq     @string_end
        iny
        cpy     #12                     ; don't go over 12, TODO: turn to a constant somewhere
        bcc     @len_loop

@string_end:
;         ldx     #$00                  ; caller probably only reads A, but let's make this 16 bit
        tya
        rts

