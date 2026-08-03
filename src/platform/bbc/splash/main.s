;
; splash.s
;
; Minimal BBC Micro custom Mode 5 splash-screen POC.
;
; Program:
;     load address: &6931
;     execution:    &6931
;
; Raw image:
;     filename:     SCREEN
;     address:      &7100
;     size:         3840 bytes
;     dimensions:   160 x 96, Mode 5 screen-memory order
;
; Build with ca65/ld65; see splash.cfg below.
;

        .setcpu "6502"

; ---------------------------------------------------------------------------
; MOS entry points
; ---------------------------------------------------------------------------

OSWRCH  = $FFEE
OSRDCH  = $FFE0
OSBYTE  = $FFF4
OSCLI   = $FFF7

; ---------------------------------------------------------------------------
; Hardware
; ---------------------------------------------------------------------------

CRTC_ADDR = $FE00
CRTC_DATA = $FE01

ULA_CTRL  = $FE20
ULA_PAL   = $FE21

; ---------------------------------------------------------------------------
; Custom screen layout
; ---------------------------------------------------------------------------

SCREEN_START       = $7100
SCREEN_SIZE        = $0F00       ; 3840 bytes
SCREEN_END         = SCREEN_START + SCREEN_SIZE

SCREEN_CHAR_ADDR   = SCREEN_START / 8

SCREEN_CRTC_HI     = >SCREEN_CHAR_ADDR
SCREEN_CRTC_LO     = <SCREEN_CHAR_ADDR

SCREEN_ROWS        = 12          ; 12 * 8 = 96 raster lines

        .assert SCREEN_END = $8000, error, "Screen must end at &8000"
        .assert SCREEN_CRTC_HI = $0E, error, "Unexpected CRTC high byte"
        .assert SCREEN_CRTC_LO = $20, error, "Unexpected CRTC low byte"

; ---------------------------------------------------------------------------
; Program
; ---------------------------------------------------------------------------

        .segment "CODE"

        .export _start

_start:
        ;
        ; Discard the RETURN/type-ahead used to launch *SPLASH before making
        ; any MOS calls that could otherwise consume it as the splash key.
        ;
        ; OSBYTE 15 flushes the keyboard input buffer when X is zero.
        ;
        lda #15
        ldx #0
        jsr OSBYTE

        ; Clear the target before selecting the custom display. This removes
        ; any old MODE 7 characters from the part of the target that overlaps
        ; the normal screen and gives the loader a black image to fill.
        lda #0
        ldx #15                 ; 15 pages = 3840 bytes
        ldy #0
@clear_page:
        sta SCREEN_START,y
        iny
        bne @clear_page
        inc @clear_page+2      ; advance the high byte of STA's address
        dex
        bne @clear_page

        ; Load the already converted raw Mode 5 file. The target has been
        ; cleared first, so the part overlapping the normal MODE 7 screen is
        ; blank while MOS performs the DFS access.
        ;
        ; OSCLI does not require the leading '*' used at the BASIC prompt.
        ldx #<load_command
        ldy #>load_command
        jsr OSCLI

        ;
        ; Configure the Video ULA palette before selecting the shortened
        ; display window.
        ;
        ; Palette byte:
        ;
        ;   high nibble = logical palette index
        ;   low bits    = physical colour EOR 7
        ;
        ; Mode 5 byte shifting visits alias indices as well as the four
        ; canonical logical colours. Program all 16 entries so the generated
        ; solid-byte bands resolve consistently to:
        ;
        ;   0 = black
        ;   1 = red
        ;   2 = yellow
        ;   3 = white
        ;
        ldx #0
@set_palette:
        lda palette_values,x
        sta ULA_PAL
        inx
        cpx #16
        bne @set_palette

        ;
        ; Set the CRTC registers, including the shortened display window. The
        ; complete SCREEN file is already resident before this takes effect.
        ;
        ; These are based on the standard PAL Mode 5 timing. Only:
        ;
        ;   R6      displayed height
        ;   R12/R13 screen start
        ;
        ; are materially changed for this POC.
        ;
        ldx #0

@set_crtc:
        stx CRTC_ADDR
        lda crtc_values,x
        sta CRTC_DATA

        inx
        cpx #14
        bne @set_crtc

        ;
        ; Select the Mode 5 Video ULA pixel format.
        ;
        ; &C4 is the standard Mode 5 ULA control value.
        ;
        lda #$C4
        sta ULA_CTRL

        ; The RETURN that launched *SPLASH can still be in the keyboard
        ; buffer because it was typed after the initial flush. Discard it
        ; before waiting, so OSRDCH cannot consume the command terminator.
        lda #15
        ldx #0
        jsr OSBYTE

        ; Wait for a new key without making any further MOS display calls. The
        ; custom CRTC and ULA state therefore remains active for the whole
        ; time the splash is visible.
        jsr OSRDCH

        ;
        ; Restore a conventional MOS-controlled screen before returning.
        ;
        lda #22                 ; VDU 22
        jsr OSWRCH

        lda #7                  ; MODE 7
        jsr OSWRCH

        rts

; ---------------------------------------------------------------------------
; CRTC register values R0 through R13
; ---------------------------------------------------------------------------
;
; Standard PAL-style Mode 5 geometry:
;
; R0  horizontal total                 63
; R1  horizontal displayed             40 byte-columns
; R2  horizontal sync position         49
; R3  sync widths                      36
; R4  vertical total                   38
; R5  vertical total adjustment         0
; R6  vertical displayed               12 rows = 96 lines
; R7  vertical sync position           34
; R8  interlace/display mode            0
; R9  scanlines per character - 1       7
; R10 cursor start                     32, cursor disabled
; R11 cursor end                        0
; R12 display address high            &0E
; R13 display address low             &20
;
; Keeping R4/R5/R7 around normal PAL values means the frame timing remains
; normal; the undisplayed portion becomes border rather than shortening the
; actual video frame.
;

crtc_values:
        .byte 63
        .byte 40
        .byte 49
        .byte 36
        .byte 38
        .byte 0
        .byte SCREEN_ROWS
        .byte 34
        .byte 0
        .byte 7
        .byte 32
        .byte 0
        .byte SCREEN_CRTC_HI
        .byte SCREEN_CRTC_LO

; Complete Mode 5 palette command table. The generated solid bytes use:
;   &00 -> indices 0/1, &0F -> 3/7, &F0 -> 9/12, &FF -> 15.
palette_values:
        .byte $07, $17, $27, $36
        .byte $47, $57, $67, $76
        .byte $87, $94, $A7, $B7
        .byte $C4, $D7, $E7, $F0

; ---------------------------------------------------------------------------
; OSCLI command
; ---------------------------------------------------------------------------

load_command:
        .byte "LOAD SCREEN 7100", 13
