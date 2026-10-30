; Select the standard or 130XE-compatible build from a PicoBoot DD disk.
; PicoBoot remains resident at $0800 until it starts the selected XEX.
        .export loader
PORTB   = $D301
SIOV    = $E459
BUF     = $0700
DOLOAD  = $084C                 ; PicoBoot DD's documented build, see README
SECMASK = $092B
SPLASH  = $A000
srcptr  = $CB
dstptr  = $CD
SPLDL   = $0500
SDLSTL  = $0230
SDMCTL  = $022F
COLOR0  = $02C4
COLOR1  = $02C5
COLOR2  = $02C6
COLOR4  = $02C8

        .segment "CODE"
loader:
        ; BASIC must be switched out for probing and the 64K bitmap.
        lda PORTB
        ora #2
        sta PORTB
        ; Preserve both bytes, including on a 64K machine where they alias.
        lda #$FF
        sta PORTB
        lda $4000
        sta base_byte
        lda #$E3              ; first 130XE CPU bank, ANTIC stays in main RAM
        sta PORTB
        lda $4000
        sta bank_byte
        lda #$55
        sta $4000
        lda #$FF
        sta PORTB
        lda #$AA
        sta $4000
        lda #$E3
        sta PORTB
        lda $4000
        cmp #$55
        php
        lda bank_byte
        sta $4000
        lda #$FF
        sta PORTB
        lda base_byte
        sta $4000
        plp
        bne standard
        ; A second independent bank is required for Setup.  Test aliasing and
        ; restore both bytes before deciding which executable to load.
        lda #$E3
        sta PORTB
        lda $4000
        sta base_byte
        lda #$E7
        sta PORTB
        lda $4000
        sta bank_byte
        lda #$AA
        sta $4000
        lda #$E3
        sta PORTB
        lda #$55
        sta $4000
        lda #$E7
        sta PORTB
        lda $4000
        cmp #$AA
        php
        lda bank_byte
        sta $4000
        lda #$E3
        sta PORTB
        lda base_byte
        sta $4000
        lda #$FF
        sta PORTB
        plp
        bne standard
        lda #1
        sta use_bank
standard:
        ; $A000 is visible to ANTIC regardless of the extended-RAM mapping.
        ; Both apps leave it untouched until the startup handoff clears BSS.
        lda #>SPLASH
        sta dstptr+1
        lda #0
        sta dstptr
        lda #<splash_image
        sta srcptr
        lda #>splash_image
        sta srcptr+1
        ldx #15                 ; 3840 bytes, 15 whole pages
        ldy #0
copy_image:
        lda (srcptr),y
        sta (dstptr),y
        iny
        bne copy_image
        inc srcptr+1
        inc dstptr+1
        dex
        bne copy_image
        ldy #0
copy_tail:
        lda (srcptr),y
        sta (dstptr),y
        iny
        cpy #160                ; 4000 bytes total
        bne copy_tail
        ldx #splash_dl_end-splash_dl-1
copy_dl:
        lda splash_dl,x
        sta SPLDL,x
        dex
        cpx #$FF
        bne copy_dl
        lda #0
        sta COLOR4
        lda #$06
        sta COLOR0
        lda #$0A
        sta COLOR1
        lda #$0E
        sta COLOR2
        lda #$21                ; narrow playfield: 32 bytes per line
        sta SDMCTL
        lda #<SPLDL
        sta SDLSTL
        lda #>SPLDL
        sta SDLSTL+1
        ; Read the first MyDOS directory sector from D1, 256 bytes.
        lda #$31
        sta $0300
        lda #1
        sta $0301
        sta $0309
        sta $030B
        lda #$52
        sta $0302
        lda #$40
        sta $0303
        lda #0
        sta $0304
        sta $0308
        lda #7
        sta $0305
        sta $0306
        lda #$69
        sta $030A
        jsr SIOV
        bmi fail
        ldy #0
entry:  lda BUF,y
        and #$40              ; in-use file, not an erased entry
        beq next
        sty entry_offset
        ldx #0
compare:
        iny
        iny
        iny
        iny
        iny                    ; file name starts at byte 5
name_loop:
        lda use_bank
        beq compare_std
        lda bank_name,x
        bne check_char
compare_std:
        lda std_name,x
check_char:
        cmp BUF,y
        bne mismatch
        iny
        inx
        cpx #11
        bne name_loop
        ldy entry_offset
        lda BUF,y
        and #4
        beq short_links
        lda #$FF
        bne save_mask
short_links:
        lda #3
save_mask:
        sta SECMASK
        lda BUF+3,y
        sta BUF+254
        lda BUF+4,y
        sta BUF+253
        lda use_bank
        beq launch
        lda #$E3
        sta PORTB
launch: jmp DOLOAD
mismatch:
        ldy entry_offset
next:   tya
        clc
        adc #16
        tay
        cpy #128
        bne entry
fail:   jmp fail              ; disk is malformed or unreadable

bank_name: .byte "BANKED  XEX"
std_name:  .byte "STANDARDXEX"
base_byte: .byte 0
bank_byte: .byte 0
use_bank: .byte 0
entry_offset: .byte 0

; ANTIC mode E: 128 x 125 pixels, four shades, 32 bytes per line.
splash_dl:
        .repeat 4
        .byte $70
        .endrepeat
        .byte $4E, <SPLASH, >SPLASH
        .repeat 124
        .byte $0E
        .endrepeat
        .byte $41, <SPLDL, >SPLDL
splash_dl_end:
splash_image:
        .incbin "src/atari-bootstrap/assets/splash.bin"
