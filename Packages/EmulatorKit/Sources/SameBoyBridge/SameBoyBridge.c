#include "SameBoyBridge.h"

// The pinned core keeps its three render-color tables in the unsaved struct section.
#ifndef GB_INTERNAL
#define GB_INTERNAL
#endif
#if __has_include(<sameboy/gb.h>)
#include <sameboy/gb.h>
#else
#include "gb.h"
#endif

#include "SameBoyBootPalettes.h"
#include "SBGameBoyPrinter.h"

#include <ctype.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define SB_WIDTH 160u
#define SB_HEIGHT 144u
#define SB_AUDIO_CAPACITY 32768u
#define SB_SAMPLE_RATE 48000u
// Reading FF50 returns bit 0 set once the boot ROM has unmapped itself.
#define SB_IO_BOOT_ROM_DISABLE 0xff50u
// SameBoy's boot ROMs hand off within a few seconds; 20 emulated seconds (in 8 MHz ticks) is a backstop.
#define SB_BOOT_SKIP_TICK_LIMIT (20ull * 8388608ull)
// Larger than any battery trailer SameBoy reads after the cartridge RAM (48 bytes at most).
#define SB_BATTERY_READ_PADDING 64u
// The most a GB/GBC cartridge maps (MBC5's 512 banks of 16 KB), and the largest image the app
// imports or a patch produces.
#define SB_MAX_ROM_SIZE (8u * 1024u * 1024u)
// Enough for the longest Blargg report, which the harness drains every frame.
#define SB_SERIAL_CAPACITY 4096u
// Every RGB555 color.
#define SB_RGB555_COLORS 32768u
#define SB_CAMERA_PIXELS (128u * 112u)

typedef struct {
    uint8_t shot[SB_CAMERA_PIXELS];
    uint8_t sequence[SB_CAMERA_PIXELS * 3];
    uint8_t next_channel;
} SBCameraCapture;

typedef struct {
    uint8_t luminance[SB_PRINTER_MAX_PIXELS];
    uint8_t height, top_margin, bottom_margin, exposure;
    bool follows_copy;
} SBPrinterBuffer;

struct SBInstance {
    GB_gameboy_t *gb;
    uint32_t *pixels;
    SBStereoSample audio[SB_AUDIO_CAPACITY];
    _Atomic size_t audio_read;
    _Atomic size_t audio_write;
    _Atomic uint64_t rumble_bits;
    bool vblank;
    bool has_run; // Whether any emulation has run since the image was loaded or reset.
    bool previewing;
    SBDMGPalette dmg_palette;
    SBColorCorrection correction;
    bool gbc_colors_on_agb;
    // With Game Boy Color colors on a Game Boy Advance, the core renders uncorrected colors into
    // `pixels` and each frame is colored into `display_pixels` through `gbc_colors`, every RGB555
    // color as a Game Boy Color's screen shows it with `gbc_colors_correction`.
    bool remaps_colors;
    uint32_t *display_pixels;
    uint32_t *gbc_colors;
    SBColorCorrection gbc_colors_correction;
    uint8_t serial[SB_SERIAL_CAPACITY];
    size_t serial_count;
    uint8_t serial_byte;
    uint8_t serial_bits;
    uint8_t camera_frame[SB_CAMERA_PIXELS * 3];
    SBCameraCapture camera;
    bool camera_pending;
    bool printer_connected;
    bool printer_overflow;
    SBGameBoyPrinter printer;
    SBPrinterBuffer printer_readout;
    SBPrinterBuffer printer_queue[16];
    size_t printer_count;
    SBPrinterEvent printer_events[64];
    size_t printer_event_count;
    // Every tick the core has run; sb_printer_time turns it into the printer's time.
    uint64_t ticks;
};

// A finished copy, its pixels already through the print's palette: 0 white to 3 black.
static void sb_printer_print(void *context, const uint8_t *pixels, uint8_t height,
                             uint8_t top, uint8_t bottom, uint8_t exposure, bool follows_copy)
{
    SBInstance *instance = context;
    if (!instance || instance->previewing || !height || height > 200) return;
    if (instance->printer_count == 16) {
        instance->printer_overflow = true;
        return;
    }
    SBPrinterBuffer *output = &instance->printer_queue[instance->printer_count++];
    output->height = height;
    output->top_margin = top;
    output->bottom_margin = bottom;
    output->exposure = exposure;
    output->follows_copy = follows_copy;
    for (size_t i = 0; i < 160u * height; i++) output->luminance[i] = (uint8_t)(255u - pixels[i] * 85u);
}

// Keeps the newest events; the oldest goes when the log is full.
static void sb_printer_event(void *context, const SBPEvent *event)
{
    SBInstance *instance = context;
    if (!instance || instance->previewing) return;
    if (instance->printer_event_count == 64) {
        memmove(instance->printer_events, instance->printer_events + 1,
                63 * sizeof(instance->printer_events[0]));
        instance->printer_event_count--;
    }
    instance->printer_events[instance->printer_event_count++] = (SBPrinterEvent){
        (double)event->time / (double)SBP_TICKS_PER_SECOND, event->kind, event->command,
        event->compression, event->status, event->length, event->checksum_ok, event->ignored,
    };
}

// The printer keeps real time. The core counts twice its clock rate, which is faster on a Super
// Game Boy than SBP_TICKS_PER_SECOND assumes.
static uint64_t sb_printer_time(SBInstance *instance, uint64_t ticks)
{
    uint64_t rate = 2ull * GB_get_unmultiplied_clock_rate(instance->gb);
    if (rate == SBP_TICKS_PER_SECOND) return ticks;
    return ticks / rate * SBP_TICKS_PER_SECOND + ticks % rate * SBP_TICKS_PER_SECOND / rate;
}

static uint64_t sb_printer_now(SBInstance *instance)
{
    return sb_printer_time(instance, instance->ticks + instance->gb->cycles_since_run);
}

static void sb_printer_bit_start(GB_gameboy_t *gb, bool bit)
{
    SBInstance *instance = GB_get_user_data(gb);
    if (instance) sbp_bit_from_game_boy(&instance->printer, sb_printer_now(instance), bit);
}

static bool sb_printer_bit_end(GB_gameboy_t *gb)
{
    SBInstance *instance = GB_get_user_data(gb);
    return instance ? sbp_bit_to_game_boy(&instance->printer) : true;
}

void SBSetJoypadBouncing(SBInstance *instance, bool enabled)
{
    if (!instance || !instance->gb) return;
    GB_set_emulate_joypad_bouncing(instance->gb, enabled);
}

void SBSetPrinterConnected(SBInstance *instance, bool connected)
{
    if (!instance || !instance->gb) return;
    GB_disconnect_serial(instance->gb);
    instance->printer_connected = connected;
    instance->printer_count = 0;
    instance->printer_event_count = 0;
    instance->printer_overflow = false;
    sbp_reset(&instance->printer, sb_printer_print, instance);
    sbp_set_event_callback(&instance->printer, sb_printer_event);
    if (!connected) return;
    // The printer here follows the printer's firmware (SBGameBoyPrinter.c) rather than the
    // core's own, which has no timeouts or packet errors.
    GB_set_serial_transfer_bit_start_callback(instance->gb, sb_printer_bit_start);
    GB_set_serial_transfer_bit_end_callback(instance->gb, sb_printer_bit_end);
}

SBPrinterActivity SBGetPrinterActivity(SBInstance *instance)
{
    if (!instance || !instance->printer_connected) return SB_PRINTER_IDLE;
    if (sbp_is_printing(&instance->printer)) return SB_PRINTER_PRINTING;
    if (sbp_is_receiving(&instance->printer)) return SB_PRINTER_RECEIVING;
    return SB_PRINTER_IDLE;
}

bool SBPopPrinterOutput(SBInstance *instance, SBPrinterOutput *output)
{
    if (!instance || !output || !instance->printer_count) return false;
    instance->printer_readout = instance->printer_queue[0];
    SBPrinterBuffer *readout = &instance->printer_readout;
    *output = (SBPrinterOutput){readout->luminance, readout->height, readout->top_margin,
                                readout->bottom_margin, readout->exposure, readout->follows_copy};
    instance->printer_count--;
    memmove(instance->printer_queue, instance->printer_queue + 1,
            instance->printer_count * sizeof(instance->printer_queue[0]));
    return true;
}

bool SBPopPrinterEvent(SBInstance *instance, SBPrinterEvent *event)
{
    if (!instance || !event || !instance->printer_event_count) return false;
    *event = instance->printer_events[0];
    instance->printer_event_count--;
    memmove(instance->printer_events, instance->printer_events + 1,
            instance->printer_event_count * sizeof(instance->printer_events[0]));
    return true;
}

bool SBConsumePrinterOverflow(SBInstance *instance)
{
    if (!instance) return false;
    bool overflow = instance->printer_overflow;
    instance->printer_overflow = false;
    return overflow;
}

static uint8_t sb_camera_pixel(GB_gameboy_t *gb, uint8_t x, uint8_t y)
{
    SBInstance *instance = GB_get_user_data(gb);
    if (!instance || x >= 128 || y >= 112) return 128;
    return instance->camera.shot[y * 128u + x];
}

static void sb_camera_requested(GB_gameboy_t *gb)
{
    SBInstance *instance = GB_get_user_data(gb);
    size_t ram_size = 0;
    uint8_t *ram = GB_get_direct_access(gb, GB_DIRECT_ACCESS_CART_RAM, &ram_size, NULL);
    uint8_t *request = ram && ram_size >= 0x100 ? ram + 0xf0 : NULL;
    bool valid = request && !memcmp(request, "RGB?", 4) && request[4] == 1 && request[5] <= 3;
    // A new request clears the entire reply and reserved area. A leftover HOST reply cannot
    // select a channel for a legacy exposure or reuse an earlier sequence.
    for (unsigned i = 6; valid && i < 16; i++) valid = request[i] == 0;
    uint8_t channel = valid ? request[5] : 0;
    const uint8_t *source = instance->camera_frame;
    if (channel) {
        if (channel == 1 || channel != instance->camera.next_channel) {
            memcpy(instance->camera.sequence, instance->camera_frame, sizeof(instance->camera.sequence));
        }
        source = instance->camera.sequence;
        instance->camera.next_channel = channel == 3 ? 0 : channel + 1;
    } else {
        instance->camera.next_channel = 0;
    }
    for (size_t i = 0; i < SB_CAMERA_PIXELS; i++) {
        const uint8_t *rgb = source + i * 3;
        instance->camera.shot[i] = channel ? rgb[channel - 1]
            : (77u * rgb[0] + 150u * rgb[1] + 29u * rgb[2] + 128u) >> 8;
    }
    if (valid) memcpy(request + 6, "HOST\x01\x00", 6);
    instance->camera_pending = true;
}

static unsigned sb_run(SBInstance *instance)
{
    unsigned ticks = GB_run(instance->gb);
    instance->ticks += ticks;
    // SameBoy sets the busy bit after calling the request callback, so completion must wait
    // until that CPU step returns. The shot stays fixed while the cartridge reads its tiles.
    if (instance->camera_pending) {
        instance->camera_pending = false;
        GB_camera_updated(instance->gb);
    }
    return ticks;
}

bool SBHasCamera(SBInstance *instance)
{
    return instance && instance->gb && instance->gb->cartridge_type->mbc_type == GB_CAMERA;
}

bool SBHasAccelerometer(SBInstance *instance)
{
    return instance && instance->gb && GB_has_accelerometer(instance->gb);
}

void SBSetAccelerometer(SBInstance *instance, double x, double y)
{
    if (!instance || !instance->gb) return;
    GB_set_accelerometer_values(instance->gb, x, y);
}

bool SBSetCameraFrame(SBInstance *instance, const uint8_t *bytes, size_t size)
{
    if (!instance) return false;
    if (!bytes && size == 0) {
        memset(instance->camera_frame, 128, sizeof(instance->camera_frame));
        memset(instance->camera.shot, 128, sizeof(instance->camera.shot));
        memset(instance->camera.sequence, 128, sizeof(instance->camera.sequence));
        instance->camera.next_channel = 0;
        return true;
    }
    if (!bytes || size != SB_CAMERA_PIXELS) return false;
    for (size_t i = 0; i < SB_CAMERA_PIXELS; i++) {
        memset(instance->camera_frame + i * 3, bytes[i], 3);
    }
    return true;
}

bool SBSetCameraRGBFrame(SBInstance *instance, const uint8_t *bytes, size_t size)
{
    if (!bytes && size == 0) return SBSetCameraFrame(instance, NULL, 0);
    if (!instance || !bytes || size != sizeof(instance->camera_frame)) return false;
    memcpy(instance->camera_frame, bytes, size);
    return true;
}

static void sb_apply_dmg_palette(SBInstance *instance)
{
    GB_gameboy_t *gb = instance->gb;
    // A Super Game Boy colors the picture with the palettes the game sends it.
    if (GB_is_cgb(gb) || GB_is_sgb(gb)) return;

    const GB_palette_t *colors;
    switch (instance->dmg_palette) {
        case SB_DMG_PALETTE_DMG: colors = &GB_PALETTE_DMG; break;
        case SB_DMG_PALETTE_MGB: colors = &GB_PALETTE_MGB; break;
        case SB_DMG_PALETTE_GBL: colors = &GB_PALETTE_GBL; break;
        default: colors = &GB_PALETTE_GREY; break;
    }
    GB_set_palette(gb, colors);

    if (instance->dmg_palette < SB_DMG_PALETTE_CGB_UP) return;
    const uint8_t *combination = sb_boot_palette_combinations[instance->dmg_palette - SB_DMG_PALETTE_CGB_UP];
    for (unsigned shade = 0; shade < 4; shade++) {
        gb->background_palettes_rgb[shade] = GB_convert_rgb15(gb, sb_boot_palette_colors[combination[0]][shade], false);
        gb->object_palettes_rgb[shade] = GB_convert_rgb15(gb, sb_boot_palette_colors[combination[1]][shade], false);
        gb->object_palettes_rgb[4 + shade] = GB_convert_rgb15(gb, sb_boot_palette_colors[combination[2]][shade], false);
    }
    gb->background_palettes_rgb[4] = GB_convert_rgb15(gb, 0x7fff, false);
}

static uint32_t sb_encode_bgra(GB_gameboy_t *gb, uint8_t r, uint8_t g, uint8_t b)
{
    (void)gb;
    return 0xff000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
}

static GB_color_correction_mode_t sb_correction_mode(SBColorCorrection mode)
{
    switch (mode) {
        case SB_COLOR_CORRECTION_OFF: return GB_COLOR_CORRECTION_DISABLED;
        case SB_COLOR_CORRECTION_ACCURATE: return GB_COLOR_CORRECTION_MODERN_ACCURATE;
        case SB_COLOR_CORRECTION_REDUCE_CONTRAST: return GB_COLOR_CORRECTION_REDUCE_CONTRAST;
        case SB_COLOR_CORRECTION_LOW_CONTRAST: return GB_COLOR_CORRECTION_LOW_CONTRAST;
        case SB_COLOR_CORRECTION_BOOST_CONTRAST: return GB_COLOR_CORRECTION_MODERN_BOOST_CONTRAST;
        case SB_COLOR_CORRECTION_BALANCED:
        default: return GB_COLOR_CORRECTION_MODERN_BALANCED;
    }
}

// Colors every RGB555 value as a Game Boy Color with the instance's correction does, using a
// Game Boy Color that exists only for this.
static bool sb_build_gbc_colors(SBInstance *instance)
{
    if (instance->gbc_colors && instance->gbc_colors_correction == instance->correction) return true;
    if (!instance->gbc_colors) {
        instance->gbc_colors = malloc(SB_RGB555_COLORS * sizeof(uint32_t));
        if (!instance->gbc_colors) return false;
    }
    if (!instance->display_pixels) {
        instance->display_pixels = calloc(SB_WIDTH * SB_HEIGHT, sizeof(uint32_t));
        if (!instance->display_pixels) return false;
    }
    GB_gameboy_t *allocation = GB_alloc();
    if (!allocation) return false;
    GB_gameboy_t *gbc = GB_init(allocation, GB_MODEL_CGB_E);
    if (!gbc) {
        GB_dealloc(allocation);
        return false;
    }
    GB_set_rgb_encode_callback(gbc, sb_encode_bgra);
    GB_set_color_correction_mode(gbc, sb_correction_mode(instance->correction));
    for (uint32_t color = 0; color < SB_RGB555_COLORS; color++) {
        instance->gbc_colors[color] = GB_convert_rgb15(gbc, (uint16_t)color, false);
    }
    GB_free(gbc);
    GB_dealloc(gbc);
    instance->gbc_colors_correction = instance->correction;
    return true;
}

// Original colors are the same on both screens, so only a corrected picture on a Game Boy Advance
// needs coloring as a Game Boy Color's.
static void sb_apply_correction(SBInstance *instance)
{
    GB_gameboy_t *gb = instance->gb;
    bool agb = gb->model == GB_MODEL_AGB_A || gb->model == GB_MODEL_GBP_A;
    instance->remaps_colors = agb && instance->gbc_colors_on_agb &&
        instance->correction != SB_COLOR_CORRECTION_OFF && sb_build_gbc_colors(instance);
    GB_set_color_correction_mode(gb, instance->remaps_colors ? GB_COLOR_CORRECTION_DISABLED
                                                             : sb_correction_mode(instance->correction));
    sb_apply_dmg_palette(instance);
}

static void sb_audio_callback(GB_gameboy_t *gb, GB_sample_t *sample)
{
    SBInstance *instance = GB_get_user_data(gb);
    if (!instance || !sample || instance->previewing) return;

    size_t write = atomic_load_explicit(&instance->audio_write, memory_order_relaxed);
    size_t next = (write + 1u) % SB_AUDIO_CAPACITY;
    size_t read = atomic_load_explicit(&instance->audio_read, memory_order_acquire);
    if (next == read) return;

    instance->audio[write] = (SBStereoSample){.left = sample->left, .right = sample->right};
    atomic_store_explicit(&instance->audio_write, next, memory_order_release);
}

static void sb_rumble_callback(GB_gameboy_t *gb, double amplitude)
{
    SBInstance *instance = GB_get_user_data(gb);
    if (!instance || instance->previewing) return;

    uint64_t bits = 0;
    memcpy(&bits, &amplitude, sizeof(bits));
    atomic_store_explicit(&instance->rumble_bits, bits, memory_order_release);
}

static void sb_vblank_callback(GB_gameboy_t *gb, GB_vblank_type_t type)
{
    (void)type;
    SBInstance *instance = GB_get_user_data(gb);
    if (instance) instance->vblank = true;
}

static uint64_t sb_ticks_to_nanoseconds(GB_gameboy_t *gb, uint64_t ticks)
{
    return ticks * 1000000000ull / 2u / GB_get_clock_rate(gb); /* / 2 because ticks are 8MHz units */
}

static GB_model_t sb_model(SBModel model)
{
    switch (model) {
        case SB_MODEL_CGB:
            return GB_MODEL_CGB_E;
        case SB_MODEL_MGB:
            return GB_MODEL_MGB;
        case SB_MODEL_SGB:
            return GB_MODEL_SGB_NTSC;
        case SB_MODEL_SGB2:
            return GB_MODEL_SGB2;
        case SB_MODEL_AGB:
            return GB_MODEL_AGB_A;
        case SB_MODEL_GBP:
            return GB_MODEL_GBP_A;
        case SB_MODEL_DMG:
        default:
            return GB_MODEL_DMG_B;
    }
}

SBInstance *SBCreate(SBModel model)
{
    SBInstance *instance = calloc(1, sizeof(*instance));
    if (!instance) return NULL;

    instance->pixels = calloc(SB_WIDTH * SB_HEIGHT, sizeof(uint32_t));
    if (!instance->pixels) {
        free(instance);
        return NULL;
    }

    GB_gameboy_t *allocation = GB_alloc();
    if (!allocation) {
        free(instance->pixels);
        free(instance);
        return NULL;
    }

    instance->gb = GB_init(allocation, sb_model(model));
    if (!instance->gb) {
        GB_dealloc(allocation);
        free(instance->pixels);
        free(instance);
        return NULL;
    }

    instance->correction = SB_COLOR_CORRECTION_BALANCED;
    atomic_init(&instance->audio_read, 0);
    atomic_init(&instance->audio_write, 0);
    atomic_init(&instance->rumble_bits, 0);

    // The pixel buffer holds 160x144. SameBoy's default draws a Super Game Boy's 256x224 border
    // around the picture, which wouldn't fit.
    GB_set_border_mode(instance->gb, GB_BORDER_NEVER);
    if (GB_get_screen_width(instance->gb) != SB_WIDTH || GB_get_screen_height(instance->gb) != SB_HEIGHT) {
        GB_free(instance->gb);
        GB_dealloc(instance->gb);
        free(instance->pixels);
        free(instance);
        return NULL;
    }
    GB_set_user_data(instance->gb, instance);
    SBSetCameraFrame(instance, NULL, 0);
    GB_set_camera_get_pixel_callback(instance->gb, sb_camera_pixel);
    GB_set_camera_update_request_callback(instance->gb, sb_camera_requested);
    GB_set_rgb_encode_callback(instance->gb, sb_encode_bgra);
    GB_set_pixels_output(instance->gb, instance->pixels);
    GB_set_sample_rate(instance->gb, SB_SAMPLE_RATE);
    GB_apu_set_sample_callback(instance->gb, sb_audio_callback);
    GB_set_rumble_callback(instance->gb, sb_rumble_callback);
    // SameBoy starts with rumble disabled, which never calls the callback. Only cartridges that
    // have a motor rumble; the app routes it to a controller or the phone.
    GB_set_rumble_mode(instance->gb, GB_RUMBLE_CARTRIDGE_ONLY);
    GB_set_vblank_callback(instance->gb, sb_vblank_callback);
    // GameplayDriver paces frames itself, so the core must never sleep to keep real time. Turbo with
    // no cap and no frame skipping is that mode; a reset keeps it.
    GB_set_turbo_mode(instance->gb, true, true);
    GB_set_turbo_cap(instance->gb, 0);
    return instance;
}

void SBDestroy(SBInstance *instance)
{
    if (!instance) return;
    if (instance->gb) {
        GB_free(instance->gb);
        GB_dealloc(instance->gb);
    }
    free(instance->pixels);
    free(instance->display_pixels);
    free(instance->gbc_colors);
    free(instance);
}

bool SBLoadBootROM(SBInstance *instance, const uint8_t *bytes, size_t size)
{
    if (!instance || !instance->gb || !bytes || size == 0) return false;
    GB_load_boot_rom_from_buffer(instance->gb, bytes, size);
    return true;
}

bool SBLoadROM(SBInstance *instance, const uint8_t *bytes, size_t size)
{
    if (!instance || !instance->gb || !bytes || size < 0x150 || size > SB_MAX_ROM_SIZE) return false;
    // SameBoy copies the image into an allocation rounded up to a power of two, at least 32 KB,
    // and writes to it without checking that the allocation succeeded. Make sure that much
    // memory is available first, so a failure is reported instead of crashing the core.
    size_t rounded = 0x8000;
    while (rounded < size) rounded <<= 1;
    void *probe = malloc(rounded);
    if (!probe) return false;
    free(probe);
    GB_load_rom_from_buffer(instance->gb, bytes, size);
    SBSetCameraFrame(instance, NULL, 0);
    instance->camera_pending = false;
    GB_reset(instance->gb);
    SBSetPrinterConnected(instance, instance->printer_connected);
    sb_apply_dmg_palette(instance);
    instance->has_run = false;
    return true;
}

bool SBSkipBootROM(SBInstance *instance, const uint8_t *fast_boot_rom, size_t fast_boot_rom_size)
{
    if (!instance || !instance->gb) return false;
    GB_gameboy_t *gb = instance->gb;

    // The boot ROM is only read as it executes, so swapping it before the first instruction is the
    // same as having loaded the fast variant to begin with.
    if (!instance->has_run && fast_boot_rom && fast_boot_rom_size > 0) {
        GB_load_boot_rom_from_buffer(gb, fast_boot_rom, fast_boot_rom_size);
    }
    instance->has_run = true;

    GB_set_rendering_disabled(gb, true);
    uint64_t ticks = 0;
    bool finished = GB_safe_read_memory(gb, SB_IO_BOOT_ROM_DISABLE) & 1;
    while (!finished && ticks < SB_BOOT_SKIP_TICK_LIMIT) {
        ticks += sb_run(instance);
        finished = GB_safe_read_memory(gb, SB_IO_BOOT_ROM_DISABLE) & 1;
    }
    GB_set_rendering_disabled(gb, false);

    // Drop the boot chime.
    size_t write = atomic_load_explicit(&instance->audio_write, memory_order_acquire);
    atomic_store_explicit(&instance->audio_read, write, memory_order_release);
    return finished;
}

void SBSetInput(SBInstance *instance, SBInputState input)
{
    if (!instance || !instance->gb) return;
    GB_set_key_state(instance->gb, GB_KEY_UP, input.up);
    GB_set_key_state(instance->gb, GB_KEY_DOWN, input.down);
    GB_set_key_state(instance->gb, GB_KEY_LEFT, input.left);
    GB_set_key_state(instance->gb, GB_KEY_RIGHT, input.right);
    GB_set_key_state(instance->gb, GB_KEY_A, input.a);
    GB_set_key_state(instance->gb, GB_KEY_B, input.b);
    GB_set_key_state(instance->gb, GB_KEY_START, input.start);
    GB_set_key_state(instance->gb, GB_KEY_SELECT, input.select);
}

SBFrameView SBRunFrame(SBInstance *instance)
{
    if (!instance || !instance->gb) return (SBFrameView){0};
    // GB_run_frame's return value only covers the time since the core's last internal sync, a
    // fraction of a frame in turbo mode, so count the frame's ticks here instead.
    uint64_t ticks = 0;
    instance->has_run = true;
    instance->vblank = false;
    while (!instance->vblank) {
        ticks += sb_run(instance);
    }
    if (instance->printer_connected) {
        sbp_advance(&instance->printer, sb_printer_time(instance, instance->ticks));
    }
    // Uncorrected channels are a 5-bit value repeated into 8 bits, so the top 5 bits are the
    // value. The core's buffer is left as drawn, since it isn't redrawn while the LCD is off.
    if (instance->remaps_colors) {
        for (size_t i = 0; i < SB_WIDTH * SB_HEIGHT; i++) {
            uint32_t pixel = instance->pixels[i];
            uint32_t color = ((pixel >> 19) & 0x1f) | (((pixel >> 11) & 0x1f) << 5) | (((pixel >> 3) & 0x1f) << 10);
            instance->display_pixels[i] = instance->gbc_colors[color];
        }
    }
    return (SBFrameView){
        .width = SB_WIDTH,
        .height = SB_HEIGHT,
        .pixels = instance->remaps_colors ? instance->display_pixels : instance->pixels,
        .emulated_nanoseconds = sb_ticks_to_nanoseconds(instance->gb, ticks),
    };
}

void SBSetColorCorrection(SBInstance *instance, SBColorCorrection mode)
{
    if (!instance || !instance->gb) return;
    if (mode < SB_COLOR_CORRECTION_OFF || mode > SB_COLOR_CORRECTION_LOW_CONTRAST) return;
    instance->correction = mode;
    sb_apply_correction(instance);
}

void SBSetGBCColorsOnAGB(SBInstance *instance, bool enabled)
{
    if (!instance || !instance->gb) return;
    instance->gbc_colors_on_agb = enabled;
    sb_apply_correction(instance);
}

void SBSetDMGPalette(SBInstance *instance, SBDMGPalette palette)
{
    if (!instance || !instance->gb) return;
    if (palette < SB_DMG_PALETTE_GREY || palette > SB_DMG_PALETTE_CGB_CAMERA) return;
    instance->dmg_palette = palette;
    sb_apply_dmg_palette(instance);
}

bool SBRefreshFrame(SBInstance *instance, SBFrameView *frame)
{
    if (!instance || !frame) return false;
    size_t size = SBStateSize(instance);
    uint8_t *state = malloc(size);
    if (!state) return false;
    if (!SBSaveState(instance, state, size)) {
        free(state);
        return false;
    }
    bool has_run = instance->has_run;
    // Sensor input is external to SameBoy's serialized state. A preview may trigger a shot,
    // so preserve its latched image alongside the core state.
    SBCameraCapture camera = instance->camera;
    // The printer's state is outside the core's too.
    SBGameBoyPrinter printer = instance->printer;
    uint64_t ticks = instance->ticks;
    instance->previewing = true;
    *frame = SBRunFrame(instance);
    bool restored = SBLoadState(instance, state, size);
    instance->previewing = false;
    instance->camera = camera;
    instance->printer = printer;
    instance->ticks = ticks;
    instance->has_run = has_run;
    free(state);
    frame->emulated_nanoseconds = 0;
    return restored;
}

size_t SBDrainAudio(SBInstance *instance, SBStereoSample *output, size_t max_frames)
{
    if (!instance || !output || max_frames == 0) return 0;

    size_t count = 0;
    size_t read = atomic_load_explicit(&instance->audio_read, memory_order_relaxed);
    while (count < max_frames) {
        size_t write = atomic_load_explicit(&instance->audio_write, memory_order_acquire);
        if (read == write) break;
        output[count++] = instance->audio[read];
        read = (read + 1u) % SB_AUDIO_CAPACITY;
    }
    atomic_store_explicit(&instance->audio_read, read, memory_order_release);
    return count;
}

double SBConsumeRumbleAmplitude(SBInstance *instance)
{
    if (!instance) return 0.0;
    uint64_t bits = atomic_exchange_explicit(&instance->rumble_bits, 0, memory_order_acq_rel);
    double amplitude = 0.0;
    memcpy(&amplitude, &bits, sizeof(amplitude));
    return amplitude;
}

size_t SBBatterySize(SBInstance *instance)
{
    if (!instance || !instance->gb) return 0;
    int size = GB_save_battery_size(instance->gb);
    return size > 0 ? (size_t)size : 0;
}

bool SBSaveBattery(SBInstance *instance, uint8_t *output, size_t size)
{
    if (!instance || !instance->gb) return false;
    size_t required = SBBatterySize(instance);
    if (required == 0) return true;
    if (!output || size < required) return false;
    return GB_save_battery_to_buffer(instance->gb, output, size) == 0;
}

void SBLoadBattery(SBInstance *instance, const uint8_t *bytes, size_t size)
{
    if (!instance || !instance->gb || !bytes || size == 0) return;
    // SameBoy copies a whole RTC trailer from after the cartridge RAM whenever the save is longer
    // than the RAM, even by one byte. The zeroed padding keeps that copy inside memory we own.
    uint8_t *padded = calloc(1, size + SB_BATTERY_READ_PADDING);
    if (!padded) return;
    memcpy(padded, bytes, size);
    GB_load_battery_from_buffer(instance->gb, padded, size);
    free(padded);
}

size_t SBStateSize(SBInstance *instance)
{
    if (!instance || !instance->gb) return 0;
    return GB_get_save_state_size(instance->gb);
}

bool SBSaveState(SBInstance *instance, uint8_t *output, size_t size)
{
    if (!instance || !instance->gb || !output) return false;
    size_t required = SBStateSize(instance);
    if (required == 0 || size < required) return false;
    GB_save_state_to_buffer(instance->gb, output);
    return true;
}

bool SBLoadState(SBInstance *instance, const uint8_t *bytes, size_t size)
{
    if (!instance || !instance->gb || !bytes || size == 0) return false;
    instance->has_run = true;
    if (GB_load_state_from_buffer(instance->gb, bytes, size) != 0) return false;
    if (!instance->previewing) SBSetPrinterConnected(instance, instance->printer_connected);
    instance->camera.next_channel = 0;
    sb_apply_dmg_palette(instance);
    return true;
}

SBRegisters SBReadRegisters(SBInstance *instance)
{
    if (!instance || !instance->gb) return (SBRegisters){0};
    GB_registers_t *registers = GB_get_registers(instance->gb);
    return (SBRegisters){
        .a = registers->af >> 8, .f = registers->af & 0xff,
        .b = registers->bc >> 8, .c = registers->bc & 0xff,
        .d = registers->de >> 8, .e = registers->de & 0xff,
        .h = registers->hl >> 8, .l = registers->hl & 0xff,
        .sp = registers->sp, .pc = registers->pc,
    };
}

uint8_t SBReadMemory(SBInstance *instance, uint16_t addr)
{
    if (!instance || !instance->gb) return 0xff;
    return GB_safe_read_memory(instance->gb, addr);
}

// Each bit the game shifts out, most significant first; eight make a byte.
static void sb_serial_bit_callback(GB_gameboy_t *gb, bool bit)
{
    SBInstance *instance = GB_get_user_data(gb);
    if (!instance) return;
    instance->serial_byte = (uint8_t)(instance->serial_byte << 1) | (bit ? 1 : 0);
    if (++instance->serial_bits < 8) return;
    if (instance->serial_count < SB_SERIAL_CAPACITY) {
        instance->serial[instance->serial_count++] = instance->serial_byte;
    }
    instance->serial_bits = 0;
}

void SBCaptureSerial(SBInstance *instance, bool enabled)
{
    if (!instance || !instance->gb) return;
    GB_set_serial_transfer_bit_start_callback(instance->gb, enabled ? sb_serial_bit_callback : NULL);
    instance->serial_bits = 0;
}

size_t SBDrainSerial(SBInstance *instance, uint8_t *output, size_t max_bytes)
{
    if (!instance || !output) return 0;
    size_t count = instance->serial_count < max_bytes ? instance->serial_count : max_bytes;
    memcpy(output, instance->serial, count);
    memmove(instance->serial, instance->serial + count, instance->serial_count - count);
    instance->serial_count -= count;
    return count;
}

void SBReset(SBInstance *instance)
{
    if (!instance || !instance->gb) return;
    GB_reset(instance->gb);
    SBSetPrinterConnected(instance, instance->printer_connected);
    instance->camera.next_channel = 0;
    sb_apply_dmg_palette(instance);
    instance->has_run = false;
}

// GB_import_cheat reads codes with sscanf, which also accepts signs, spaces and "0x", and reads
// only the first nine digits of a longer Game Genie code. Only hex digits and dashes reach it,
// starting and ending with a digit: 8 digits and no dashes (GameShark), or 6 or 9 (Game Genie).
static bool sb_cheat_has_code_shape(const char *code)
{
    if (!code) return false;
    size_t length = strlen(code);
    if (length == 0 || length > 16) return false;
    if (!isxdigit((unsigned char)code[0]) || !isxdigit((unsigned char)code[length - 1])) return false;
    size_t digits = 0;
    size_t dashes = 0;
    for (size_t i = 0; i < length; i++) {
        if (isxdigit((unsigned char)code[i])) digits++;
        else if (code[i] == '-') dashes++;
        else return false;
    }
    if (digits == 8) return dashes == 0;
    return digits == 6 || digits == 9;
}

bool SBCheckCheat(const char *code)
{
    if (!sb_cheat_has_code_shape(code)) return false;
    GB_gameboy_t *allocation = GB_alloc();
    if (!allocation) return false;
    GB_gameboy_t *gb = GB_init(allocation, GB_MODEL_DMG_B);
    if (!gb) {
        GB_dealloc(allocation);
        return false;
    }
    bool readable = GB_import_cheat(gb, code, "", false) != NULL;
    GB_dealloc(gb);
    return readable;
}

bool SBSetCheats(SBInstance *instance, const char *const *codes, size_t count)
{
    if (!instance || !instance->gb || (count > 0 && !codes)) return false;
    for (size_t i = 0; i < count; i++) {
        if (!sb_cheat_has_code_shape(codes[i])) return false;
    }
    GB_gameboy_t *gb = instance->gb;
    // Adding a cheat can move SameBoy's list, so keep the old entries' own pointers.
    size_t previous_count = 0;
    const GB_cheat_t *const *current = GB_get_cheats(gb, &previous_count);
    const GB_cheat_t **previous = previous_count ? malloc(previous_count * sizeof(*previous)) : NULL;
    const GB_cheat_t **added = count ? calloc(count, sizeof(*added)) : NULL;
    if ((previous_count && !previous) || (count && !added)) {
        free(previous);
        free(added);
        return false;
    }
    if (previous_count) memcpy(previous, current, previous_count * sizeof(*previous));
    bool imported = true;
    for (size_t i = 0; i < count && imported; i++) {
        added[i] = GB_import_cheat(gb, codes[i], "", true);
        imported = added[i] != NULL;
    }
    const GB_cheat_t **removed = imported ? previous : added;
    size_t removed_count = imported ? previous_count : count;
    for (size_t i = 0; i < removed_count; i++) {
        if (removed[i]) GB_remove_cheat(gb, removed[i]);
    }
    free(previous);
    free(added);
    return imported;
}

void SBSetCheatsEnabled(SBInstance *instance, bool enabled)
{
    if (!instance || !instance->gb) return;
    GB_set_cheats_enabled(instance->gb, enabled);
}
