#include "Core/gb.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// Runs TestROMs/roms/sgb-packets.gb on SameBoy's Super Game Boy 2 with the border drawn, as the
// 256x224 picture a television shows, and checks the palette (PAL01) and border (CHR_TRN, PCT_TRN)
// the ROM sends. The app draws no border yet, so this runs SameBoy directly rather than through
// the bridge. SGB2_BOOT_ROM and SGB_FIXTURE name the files; without the generated boot ROM the
// test is skipped. With SGB_BORDER_PPM set, the picture is also written there.

enum { WIDTH = 256, HEIGHT = 224, LEFT = 48, TOP = 40 };

static uint32_t encode(GB_gameboy_t *gb, uint8_t r, uint8_t g, uint8_t b)
{
    (void)gb;
    return (uint32_t)r << 16 | (uint32_t)g << 8 | b;
}

static uint32_t rgb555(unsigned r, unsigned g, unsigned b)
{
    return (uint32_t)((r << 3) | (r >> 2)) << 16 | (uint32_t)((g << 3) | (g >> 2)) << 8 | ((b << 3) | (b >> 2));
}

static uint8_t *read_file(const char *path, size_t *size)
{
    FILE *file = path ? fopen(path, "rb") : NULL;
    if (!file) return NULL;
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);
    uint8_t *bytes = malloc((size_t)length);
    assert(bytes && fread(bytes, 1, (size_t)length, file) == (size_t)length);
    fclose(file);
    *size = (size_t)length;
    return bytes;
}

void test_sgb_border(void)
{
    size_t boot_size = 0, rom_size = 0;
    uint8_t *boot = read_file(getenv("SGB2_BOOT_ROM"), &boot_size);
    if (!boot) {
        puts("sgb border: skipped, no generated sgb2_boot.bin");
        return;
    }
    uint8_t *rom = read_file(getenv("SGB_FIXTURE"), &rom_size);
    assert(rom);

    GB_gameboy_t *gb = GB_init(GB_alloc(), GB_MODEL_SGB2);
    static uint32_t pixels[WIDTH * HEIGHT];
    GB_set_border_mode(gb, GB_BORDER_ALWAYS);
    GB_set_color_correction_mode(gb, GB_COLOR_CORRECTION_DISABLED);
    GB_set_rgb_encode_callback(gb, encode);
    GB_set_pixels_output(gb, pixels);
    GB_load_boot_rom_from_buffer(gb, boot, boot_size);
    GB_load_rom_from_buffer(gb, rom, rom_size);
    assert(GB_get_screen_width(gb) == WIDTH && GB_get_screen_height(gb) == HEIGHT);
    // Boot, three transfers and the border's fade in take well under ten seconds.
    for (unsigned frame = 0; frame < 600; frame++) GB_run_frame(gb);

    const char *ppm = getenv("SGB_BORDER_PPM");
    if (ppm) {
        FILE *out = fopen(ppm, "wb");
        assert(out);
        fprintf(out, "P6\n%d %d\n255\n", WIDTH, HEIGHT);
        for (unsigned i = 0; i < WIDTH * HEIGHT; i++) {
            uint8_t rgb[3] = {pixels[i] >> 16, pixels[i] >> 8, pixels[i]};
            fwrite(rgb, 1, 3, out);
        }
        fclose(out);
    }

#define AT(x, y) pixels[(y) * WIDTH + (x)]
    // The border: tiles of colors 1 and 2 alternate, and a frame of color 3 surrounds the picture.
    assert(AT(4, 4) == rgb555(12, 4, 18));
    assert(AT(8 + 4, 4) == rgb555(12, 4, 18) || AT(8 + 4, 4) == rgb555(30, 24, 6));
    assert(AT(5 * 8 + 4, 12 * 8) == rgb555(28, 28, 30));
    assert(AT(26 * 8 + 4, 12 * 8) == rgb555(28, 28, 30));
    // The picture in PAL01's palette 0: cream, then the bars in orange, teal and navy.
    assert(AT(LEFT + 159, TOP + 143) == rgb555(31, 29, 20));
    assert(AT(LEFT + 3 * 8, TOP + 76) == rgb555(31, 29, 20));
    assert(AT(LEFT + 7 * 8, TOP + 76) == rgb555(31, 16, 4));
    assert(AT(LEFT + 11 * 8, TOP + 76) == rgb555(2, 16, 18));
    assert(AT(LEFT + 15 * 8, TOP + 76) == rgb555(3, 3, 10));
#undef AT

    GB_free(gb);
    GB_dealloc(gb);
    free(rom);
    free(boot);
    puts("sgb border: ok");
}
