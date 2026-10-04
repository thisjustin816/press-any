; Press Any test ROM: RGBDS assembly with hUGEDriver music, a bouncing sprite and a
; pressed-button indicator. The song is hUGEDriver's own sample song (public domain).
; MIT License, see LICENSE.

INCLUDE "include/hardware.inc"
INCLUDE "include/hUGE.inc"

DEF BALL_TILE EQU 64        ; font uses tiles 0..63, the ball is tile 64
DEF X_MIN EQU 8
DEF X_MAX EQU 160
DEF Y_MIN EQU 96
DEF Y_MAX EQU 112

MACRO Text                  ; Text col, row, "string"
    dw $9800 + (\2) * 32 + (\1)
    db \3, 0
ENDM

MACRO Btn                   ; Btn col, row, mask, "label"
    dw $9800 + (\2) * 32 + (\1)
    db \3
    db \4, 0
ENDM

MACRO RGB555
    dw (\1) | ((\2) << 5) | ((\3) << 10)
ENDM

SECTION "Header", ROM0[$100]
    nop
    jp Start
    ds $150 - @, 0

SECTION "Main", ROM0
Start:
    di
    ld sp, $FFFE
.wait_vblank:
    ldh a, [rLY]
    cp 144
    jr c, .wait_vblank
    xor a
    ldh [rLCDC], a              ; LCD off

    ld hl, $8000
    ld de, Font
    ld bc, FontEnd - Font
    call Copy
    ld de, Ball                 ; HL carries on to tile 64
    ld bc, 16
    call Copy

    ld hl, $9800
    ld bc, $400
    xor a
    call Fill
IF DEF(GBC)
    ld a, 1                     ; clear the attribute map too: VRAM bank 1 is not zeroed by hardware
    ldh [rVBK], a
    ld hl, $9800
    ld bc, $400
    xor a
    call Fill
    xor a
    ldh [rVBK], a

    ld a, $80
    ldh [rBCPS], a
    ld hl, BgPalette
    ld b, 8
.bg_pal:
    ld a, [hli]
    ldh [rBCPD], a
    dec b
    jr nz, .bg_pal
    ld a, $80
    ldh [rOCPS], a
    ld hl, ObjPalette
    ld b, 8
.obj_pal:
    ld a, [hli]
    ldh [rOCPD], a
    dec b
    jr nz, .obj_pal
ELSE
    ld a, %11100100
    ldh [rBGP], a
    ldh [rOBP0], a
ENDC

    ld hl, $FE00                ; clear OAM
    ld b, 160
    xor a
.clear_oam:
    ld [hli], a
    dec b
    jr nz, .clear_oam

    ld hl, TextTable
    call DrawText

    ld a, 40
    ld [wX], a
    ld a, 100
    ld [wY], a
    ld a, 1
    ld [wDX], a
    ld [wDY], a
    ld a, $FF
    ld [wPrev], a

    ld a, $80                   ; sound on, all channels to both speakers, full volume
    ldh [rNR52], a
    ld a, $FF
    ldh [rNR51], a
    ld a, $77
    ldh [rNR50], a
    ld hl, sample_song
    call hUGE_init

    ld a, %10010011             ; LCD on, BG on, OBJ on, tile data at $8000
    ldh [rLCDC], a

MainLoop:
    call ReadPad                ; B = held buttons
.leave_vblank:
    ldh a, [rLY]
    cp 144
    jr nc, .leave_vblank
.enter_vblank:
    ldh a, [rLY]
    cp 144
    jr c, .enter_vblank

    ld a, [wPrev]
    cp b
    jr z, .no_buttons
    ld a, b
    ld [wPrev], a
    call DrawButtons
.no_buttons:

    ld a, [wDX]
    ld c, a
    ld a, [wX]
    add c
    ld [wX], a
    cp X_MIN
    jr z, .flip_x
    cp X_MAX
    jr nz, .x_done
.flip_x:
    ld a, c
    cpl
    inc a
    ld [wDX], a
.x_done:
    ld a, [wDY]
    ld c, a
    ld a, [wY]
    add c
    ld [wY], a
    cp Y_MIN
    jr z, .flip_y
    cp Y_MAX
    jr nz, .y_done
.flip_y:
    ld a, c
    cpl
    inc a
    ld [wDY], a
.y_done:
    ld hl, $FE00
    ld a, [wY]
    ld [hli], a
    ld a, [wX]
    ld [hli], a
    ld a, BALL_TILE
    ld [hli], a
    xor a
    ld [hl], a
    call hUGE_dosound           ; once per frame, after the OAM write so it cannot overrun VBlank work
    jr MainLoop

; B = buttons held: bit 0 Right, 1 Left, 2 Up, 3 Down, 4 A, 5 B, 6 Select, 7 Start.
ReadPad:
    ld a, $20
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    ld b, a
    ld a, $10
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    swap a
    or b
    ld b, a
    ld a, $30
    ldh [rP1], a
    ret

; HL = table of (dest word, zero-terminated ASCII string), ended by a zero word.
DrawText:
.next:
    ld a, [hli]
    ld e, a
    ld a, [hli]
    ld d, a
    or e
    ret z
.char:
    ld a, [hli]
    and a
    jr z, .next
    sub 32
    ld [de], a
    inc de
    jr .char

; B = buttons held. Shows each label while its button is held and blanks it otherwise.
DrawButtons:
    ld hl, ButtonTable
.next:
    ld a, [hli]
    ld e, a
    ld a, [hli]
    ld d, a
    or e
    ret z
    ld a, [hli]
    and b
    ld c, a                     ; C is non-zero while the button is held
.char:
    ld a, [hli]
    and a
    jr z, .next
    sub 32
    inc c
    dec c
    jr nz, .put
    xor a
.put:
    ld [de], a
    inc de
    jr .char

Copy:                           ; copy BC bytes from DE to HL
    ld a, [de]
    ld [hli], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, Copy
    ret

Fill:                           ; fill BC bytes at HL with A
    ld d, a
.loop:
    ld a, d
    ld [hli], a
    dec bc
    ld a, b
    or c
    jr nz, .loop
    ret

TextTable:
IF DEF(GBC)
    Text 0, 1, "RGBDS GBC TEST"
    Text 0, 6, "SYSTEM: GBC"
    Text 0, 7, "HEADER: GBC ONLY"
ELSE
    Text 0, 1, "HUGEDRIVER DMG TEST"
    Text 0, 6, "SYSTEM: GB"
    Text 0, 7, "HEADER: GB ONLY"
ENDC
    Text 0, 3, "HUGEDRIVER A3CBD0C"
    Text 0, 4, "RGBDS 1.0.4"
    Text 0, 8, "MUSIC: SAMPLE SONG"
    Text 0, 13, "HELD:"
    dw 0

ButtonTable:
    Btn 0, 15, %00000100, "UP"
    Btn 3, 15, %00001000, "DOWN"
    Btn 8, 15, %00000010, "LEFT"
    Btn 13, 15, %00000001, "RIGHT"
    Btn 0, 16, %00010000, "A"
    Btn 2, 16, %00100000, "B"
    Btn 4, 16, %01000000, "SELECT"
    Btn 11, 16, %10000000, "START"
    dw 0

Ball:
    db $3C, $3C, $7E, $5E, $FF, $9F, $FF, $BF
    db $FF, $FF, $FF, $FF, $7E, $7E, $3C, $3C

IF DEF(GBC)
BgPalette:
    RGB555 2, 4, 10
    RGB555 8, 12, 24
    RGB555 20, 24, 31
    RGB555 31, 31, 20
ObjPalette:
    RGB555 31, 31, 31
    RGB555 31, 24, 8
    RGB555 31, 14, 4
    RGB555 31, 6, 2
ENDC

INCLUDE "font.inc"

SECTION "State", WRAM0
wPrev: ds 1
wX: ds 1
wY: ds 1
wDX: ds 1
wDY: ds 1
