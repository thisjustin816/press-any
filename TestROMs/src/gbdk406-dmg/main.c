/* Press Any test ROM: text, a bouncing sprite and a pressed-button indicator.
 * MIT License, see LICENSE. Built with GBDK-2020; configured by config.h. */
#include <gb/gb.h>
#include <gb/cgb.h>
#include <gbdk/console.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "config.h"

#define SPRITE_MIN_X 8
#define SPRITE_MAX_X 160
#define SPRITE_MIN_Y 104
#define SPRITE_MAX_Y 128

static const uint8_t ball_tile[] = {
    0x3C, 0x3C, 0x7E, 0x5E, 0xFF, 0x9F, 0xFF, 0xBF,
    0xFF, 0xFF, 0xFF, 0xFF, 0x7E, 0x7E, 0x3C, 0x3C};

#if MODE_KIND != 0
static const palette_color_t bkg_pal[] = {RGB(31, 31, 24), RGB(20, 24, 31), RGB(8, 12, 24), RGB(2, 2, 10)};
static const palette_color_t spr_pal[] = {RGB(31, 31, 31), RGB(31, 24, 8), RGB(31, 10, 4), RGB(12, 2, 2)};
#endif

#if WITH_SAVE
/* Battery save layout in cart RAM: "PAST", 32-bit counter (little endian), XOR check byte. */
static volatile uint8_t *const sram = (volatile uint8_t *)0xA000;
static const char magic[4] = {'P', 'A', 'S', 'T'};

static uint8_t save_check(uint32_t n)
{
    return (uint8_t)(0x5A ^ n ^ (n >> 8) ^ (n >> 16) ^ (n >> 24));
}

static uint32_t save_load(void)
{
    uint32_t n;
    uint8_t i;
    for (i = 0; i < 4; i++)
        if (sram[i] != (uint8_t)magic[i])
            return 0;
    n = (uint32_t)sram[4] | ((uint32_t)sram[5] << 8) | ((uint32_t)sram[6] << 16) | ((uint32_t)sram[7] << 24);
    return sram[8] == save_check(n) ? n : 0;
}

static void save_store(uint32_t n)
{
    uint8_t i;
    for (i = 0; i < 4; i++)
        sram[i] = (uint8_t)magic[i];
    sram[4] = (uint8_t)n;
    sram[5] = (uint8_t)(n >> 8);
    sram[6] = (uint8_t)(n >> 16);
    sram[7] = (uint8_t)(n >> 24);
    sram[8] = save_check(n);
}
#endif

#if WITH_SAVE
static void show_saves(uint32_t n)
{
    char digits[11];
    uint8_t i = 10;
    digits[10] = 0;
    do {
        digits[--i] = (char)('0' + (n % 10));
        n /= 10;
    } while (n && i);
    gotoxy(0, 9);
    printf("SAVES: %s          ", &digits[i]);
}
#endif

static void show_buttons(uint8_t j)
{
    char buf[32];
    buf[0] = 0;
    if (j & J_UP) strcat(buf, "UP ");
    if (j & J_DOWN) strcat(buf, "DOWN ");
    if (j & J_LEFT) strcat(buf, "LEFT ");
    if (j & J_RIGHT) strcat(buf, "RIGHT ");
    if (j & J_A) strcat(buf, "A ");
    if (j & J_B) strcat(buf, "B ");
    if (j & J_SELECT) strcat(buf, "SEL ");
    if (j & J_START) strcat(buf, "START ");
    if (!buf[0]) strcpy(buf, "-");
    while (strlen(buf) < 14) strcat(buf, " ");
    buf[14] = 0;
    gotoxy(6, 16);
    printf("%s", buf);
}

void main(void)
{
    uint8_t x = 40, y = 112, j, prev = 0;
    int8_t dx = BALL_SPEED, dy = BALL_SPEED;
    uint8_t is_color = 0;
#if WITH_SAVE
    uint32_t saves;
    ENABLE_RAM;
    SWITCH_RAM(0);
    saves = save_load() + 1;
    save_store(saves);
#endif

#if MODE_KIND != 0
    VBK_REG = 0;
    if (_cpu == CGB_TYPE && VBK_REG == 0xFE) { /* both the boot value and the VBK register say CGB */
        is_color = 1;
        set_bkg_palette(0, 1, bkg_pal);
        set_sprite_palette(0, 1, spr_pal);
    }
#endif
#if MODE_KIND == 2
    if (!is_color) {
        BGP_REG = 0x1B; /* DMG: inverted shades, so it differs from the color view */
        OBP0_REG = 0x1B;
    }
#endif

    set_sprite_data(0, 1, ball_tile);
    set_sprite_tile(0, 0);
    SHOW_BKG;
    SHOW_SPRITES;

    gotoxy(0, 1);
    printf("%s", ROM_TITLE);
    gotoxy(0, 3);
    printf("%s", SDK_LINE);
    gotoxy(0, 4);
    printf("%s", VER_LINE);
    gotoxy(0, 6);
    printf("SYSTEM: %s", is_color ? "GBC" : "GB");
    gotoxy(0, 7);
    printf("%s", HEADER_LINE);
    gotoxy(0, 8);
    printf("%s", EXTRA_LINE);
#if WITH_SAVE
    show_saves(saves);
#endif
    gotoxy(0, 16);
    printf("BTN: ");
    DISPLAY_ON;

    while (1) {
        j = joypad();
#if WITH_SAVE
        if ((j & J_A) && !(prev & J_A)) {
            saves++;
            save_store(saves);
            show_saves(saves);
        }
#endif
        prev = j;
        show_buttons(j);

        x += dx;
        y += dy;
        if (x <= SPRITE_MIN_X || x >= SPRITE_MAX_X) dx = -dx;
        if (y <= SPRITE_MIN_Y || y >= SPRITE_MAX_Y) dy = -dy;
        move_sprite(0, x, y);
        wait_vbl_done();
    }
}
