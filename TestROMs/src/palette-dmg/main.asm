; MIT License, see LICENSE.
; Four BG bands and two rows of sprites using OBP0 and OBP1. A maps sprite color 1 to shade 0.
DEF rP1 EQU $FF00
DEF rLCDC EQU $FF40
DEF rLY EQU $FF44
DEF rBGP EQU $FF47
DEF rOBP0 EQU $FF48
DEF rOBP1 EQU $FF49

SECTION "Header", ROM0[$100]
    nop
    jp Start
    ds $150 - @, 0

SECTION "Main", ROM0
Start:
    di
    ld sp, $FFFE
.waitVBlank
    ldh a, [rLY]
    cp 144
    jr c, .waitVBlank
    xor a
    ldh [rLCDC], a
    ldh [$FF42], a
    ldh [$FF43], a
    ld hl, Tiles
    ld de, $8000
    ld bc, TilesEnd - Tiles
.copyTiles
    ld a, [hli]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .copyTiles

    ld hl, $9800
    ld b, 32
.row
    ld c, 32
.column
    ld a, l
    and 3
    ld [hli], a
    dec c
    jr nz, .column
    dec b
    jr nz, .row

    ld hl, $FE00
    ld b, 160
    xor a
.clearOAM
    ld [hli], a
    dec b
    jr nz, .clearOAM
    ld hl, Sprites
    ld de, $FE00
    ld b, SpritesEnd - Sprites
.copyOAM
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .copyOAM
    ld a, $E4
    ldh [rBGP], a
    ldh [rOBP0], a
    ldh [rOBP1], a
    ld a, $93
    ldh [rLCDC], a
.loop
    ldh a, [rLY]
    cp 144
    jr c, .loop
    ld a, $10
    ldh [rP1], a
    REPT 8
        ldh a, [rP1]
    ENDR
    bit 0, a
    ld a, $E4
    jr nz, .setPalettes
    ld a, $E0
.setPalettes
    ldh [rOBP0], a
    ldh [rOBP1], a
    ld a, $30
    ldh [rP1], a
.leaveVBlank
    ldh a, [rLY]
    cp 144
    jr nc, .leaveVBlank
    jr .loop

Tiles:
    REPT 8
        db $00, $00
    ENDR
    REPT 8
        db $FF, $00
    ENDR
    REPT 8
        db $00, $FF
    ENDR
    REPT 8
        db $FF, $FF
    ENDR
TilesEnd:
Sprites:
    db 48, 8, 1, $00
    db 48, 16, 2, $00
    db 48, 24, 3, $00
    db 64, 8, 1, $10
    db 64, 16, 2, $10
    db 64, 24, 3, $10
SpritesEnd:
