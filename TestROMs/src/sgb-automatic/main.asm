; MIT License, see LICENSE.
; Shows which header flags this build carries, then sends a Super Game Boy its border (CHR_TRN
; for the tiles, PCT_TRN for the map and colors) and a palette (PAL01). Other hardware ignores
; the packets. build.sh assembles it once per fixture with LINE1, LINE2 and LINE3 defined as
; strings, and rgbfix sets each fixture's header flags.

DEF rP1 EQU $FF00
DEF rLCDC EQU $FF40
DEF rLY EQU $FF44
DEF rBGP EQU $FF47
DEF rVBK EQU $FF4F
DEF rBCPS EQU $FF68
DEF rBCPD EQU $FF69

DEF LCD_ON_BG EQU $91       ; LCD on, background on, tiles at $8000, map at $9800
DEF LCD_ON_BLANK EQU $80    ; LCD on, background off
DEF SOLID_TILE EQU 64       ; the font fills tiles 0..63; shades 1, 2 and 3 follow

MACRO RGB555
    dw (\1) | ((\2) << 5) | ((\3) << 10)
ENDM

SECTION "Header", ROM0[$100]
    nop
    jp Start
    ds $150 - @, 0

SECTION "State", HRAM
hBootA: ds 1

SECTION "Main", ROM0
Start:
    di
    ld sp, $FFFE
    ldh [hBootA], a             ; $11 when a Game Boy Color runs it in color
    call LCDOff
    ld hl, $8000
    ld bc, $2000
    call Clear
    ldh a, [hBootA]
    cp $11
    jr nz, .notColor
    ld a, 1                     ; VRAM bank 1 holds the attribute map, which isn't cleared at boot
    ldh [rVBK], a
    ld hl, $9800
    ld bc, $400
    call Clear
    xor a
    ldh [rVBK], a
    ld a, $80
    ldh [rBCPS], a
    ld hl, GrayPalette
    ld b, 8
.palette
    ld a, [hli]
    ldh [rBCPD], a
    dec b
    jr nz, .palette
.notColor
    ld a, LCD_ON_BLANK
    ldh [rLCDC], a
    ld b, 4
    call WaitFrames

    ; Hide the transfers behind color 0 while the screen shows raw data.
    ld hl, MaskColor0
    call SendPacket

    ; CHR_TRN: the border's tiles, 4 KB shown as 256 background tiles.
    call LCDOff
    ld hl, $8000
    ld de, BorderTiles
    ld bc, BorderTilesEnd - BorderTiles
    call Copy
    call ShowTransferMap
    call SendTransfer.chr

    ; PCT_TRN: the border's tile map and its 16 colors.
    call LCDOff
    ld hl, $8000
    ld de, BorderMap
    ld bc, BorderMapEnd - BorderMap
    call Copy
    ld a, LCD_ON_BG
    ldh [rLCDC], a
    call SendTransfer.pct

    ; The picture: text and four shade bars.
    call LCDOff
    ld hl, $8000
    ld bc, $1000
    call Clear
    ld hl, $8000
    ld de, Font
    ld bc, FontEnd - Font
    call Copy
    ld de, SolidTiles           ; HL carries on to tile 64
    ld bc, SolidTilesEnd - SolidTiles
    call Copy
    ld hl, $9800
    ld bc, $400
    call Clear
    ld hl, $9800 + 1 * 32 + 1
    ld de, Line1
    call DrawText
    ld hl, $9800 + 3 * 32 + 1
    ld de, Line2
    call DrawText
    ld hl, $9800 + 5 * 32 + 1
    ld de, Line3
    call DrawText
    call DrawBars
    ld a, $E4
    ldh [rBGP], a
    ld a, LCD_ON_BG
    ldh [rLCDC], a

    ld hl, Pal01
    call SendPacket
    ld hl, MaskCancel
    call SendPacket
.forever
    jr .forever

; Shows tiles 0..255 in rows of 20 from the top left, as a transfer reads the screen.
ShowTransferMap:
    ld hl, $9800
    ld bc, $400
    call Clear
    ld hl, $9800
    xor a
    ld d, 13                    ; 13 rows of 20 cover 256 tiles
.row
    ld e, 20
.column
    ld [hli], a
    inc a
    dec e
    jr nz, .column
    ld bc, 32 - 20
    add hl, bc
    dec d
    jr nz, .row
    ld a, $E4                   ; shade n shows as color n, so the screen holds the bytes exactly
    ldh [rBGP], a
    ld a, LCD_ON_BG
    ldh [rLCDC], a
    ret

; Sends a transfer packet once the data has been on screen for two frames, then waits for the
; Super Game Boy to read it.
SendTransfer:
.chr
    ld hl, ChrTrn
    jr .send
.pct
    ld hl, PctTrn
.send
    ld b, 2
    call WaitFrames
    call SendPacket
    ld b, 8
    jp WaitFrames

; Sends the 16-byte packet at HL through the joypad register, least significant bit first: a
; reset pulse, 128 bits, then a 0 stop bit. Then waits four frames, as the Super Game Boy needs.
SendPacket:
    xor a
    ldh [rP1], a
    ld a, $30
    ldh [rP1], a
    ld b, 16
.byte
    ld a, [hli]
    ld c, a
    ld d, 8
.bit
    ld a, $10                   ; P15 low sends a 1
    bit 0, c
    jr nz, .write
    ld a, $20                   ; P14 low sends a 0
.write
    ldh [rP1], a
    ld a, $30
    ldh [rP1], a
    rr c
    dec d
    jr nz, .bit
    dec b
    jr nz, .byte
    ld a, $20
    ldh [rP1], a
    ld a, $30
    ldh [rP1], a
    ld b, 4
    jp WaitFrames

; Waits for B frames to start. The LCD must be on.
WaitFrames:
.leave
    ldh a, [rLY]
    cp 144
    jr nc, .leave
.enter
    ldh a, [rLY]
    cp 144
    jr c, .enter
    dec b
    jr nz, WaitFrames
    ret

LCDOff:
    ldh a, [rLY]
    cp 144
    jr c, LCDOff
    xor a
    ldh [rLCDC], a
    ret

; Fills BC bytes from HL with 0.
Clear:
    xor a
    ld [hli], a
    dec bc
    ld a, b
    or c
    jr nz, Clear
    ret

; Copies BC bytes from DE to HL.
Copy:
    ld a, [de]
    ld [hli], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, Copy
    ret

; Writes the zero-terminated ASCII string at DE to the map at HL as font tiles.
DrawText:
    ld a, [de]
    and a
    ret z
    sub 32
    ld [hli], a
    inc de
    jr DrawText

; Four bars of shades 0 to 3, four tiles wide and three tall, from column 2 of row 9.
DrawBars:
    ld hl, $9800 + 9 * 32 + 2
    ld c, 3
.row
    ld a, 0                     ; the font's space is shade 0
    call .bar
    ld a, SOLID_TILE
    call .bar
    ld a, SOLID_TILE + 1
    call .bar
    ld a, SOLID_TILE + 2
    call .bar
    ld de, 32 - 16
    add hl, de
    dec c
    jr nz, .row
    ret
.bar
    ld b, 4
.tile
    ld [hli], a
    dec b
    jr nz, .tile
    ret

Line1: db LINE1, 0
Line2: db LINE2, 0
Line3: db LINE3, 0

; White, light gray, dark gray and black, for a Game Boy Color running it in color.
GrayPalette:
    RGB555 31, 31, 31
    RGB555 21, 21, 21
    RGB555 10, 10, 10
    RGB555 0, 0, 0

; Packets: the command times 8 plus the packet count, then the data, padded to 16 bytes.
MaskColor0: db ($17 << 3) | 1, 3
    ds 14, 0
MaskCancel: db ($17 << 3) | 1, 0
    ds 14, 0
ChrTrn: db ($13 << 3) | 1, 0
    ds 14, 0
PctTrn: db ($14 << 3) | 1
    ds 15, 0
; Color 0, then palette 0's colors 1 to 3, then palette 1's.
Pal01: db ($00 << 3) | 1
    RGB555 31, 29, 20           ; cream
    RGB555 31, 16, 4            ; orange
    RGB555 2, 16, 18            ; teal
    RGB555 3, 3, 10             ; navy
    RGB555 31, 0, 0
    RGB555 0, 31, 0
    RGB555 0, 0, 31
    db 0

SolidTiles:
    REPT 8
        db $FF, $00
    ENDR
    REPT 8
        db $00, $FF
    ENDR
    REPT 8
        db $FF, $FF
    ENDR
SolidTilesEnd:

; Super Game Boy border tiles, 4 bits per pixel: each row's bit planes 0 and 1, then 2 and 3.
; Tile 0 is clear, tile 1 color 1, tile 2 a checker of colors 1 and 2, tile 3 color 3.
BorderTiles:
    ds 32, 0
    REPT 8
        db $FF, $00
    ENDR
    ds 16, 0
    REPT 4
        db $AA, $55, $55, $AA
    ENDR
    ds 16, 0
    REPT 8
        db $FF, $FF
    ENDR
    ds 16, 0
BorderTilesEnd:

; 32x32 map entries: the tile in the low byte, palette 4 in bits 10 to 12. The Game Boy's picture
; shows through clear tile 0 in columns 6..25 of rows 5..22, framed by tile 3 and surrounded by
; alternating tiles 1 and 2. Rows 28 and below are off screen.
BorderMap:
FOR Y, 32
    FOR X, 32
        IF Y >= 28
            dw 0
        ELIF X >= 6 && X < 26 && Y >= 5 && Y < 23
            dw $1000
        ELIF X >= 5 && X <= 26 && Y >= 4 && Y <= 23
            dw $1003
        ELSE
            dw $1001 + ((X + Y) & 1)
        ENDC
    ENDR
ENDR
; Palette 4: color 0 is never drawn, as the picture's color 0 shows instead.
    RGB555 0, 0, 0
    RGB555 12, 4, 18            ; purple
    RGB555 30, 24, 6            ; gold
    RGB555 28, 28, 30           ; frame
    ds 12 * 2, 0
    ds 3 * 16 * 2, 0            ; palettes 5 to 7
BorderMapEnd:

INCLUDE "font.inc"
