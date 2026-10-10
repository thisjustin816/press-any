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
    uint8_t serial[SB_SERIAL_CAPACITY];
    size_t serial_count;
    uint8_t serial_byte;
    uint8_t serial_bits;
};

static void sb_apply_dmg_palette(SBInstance *instance)
{
    GB_gameboy_t *gb = instance->gb;
    if (GB_is_cgb(gb)) return;

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

    atomic_init(&instance->audio_read, 0);
    atomic_init(&instance->audio_write, 0);
    atomic_init(&instance->rumble_bits, 0);

    GB_set_user_data(instance->gb, instance);
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
    GB_reset(instance->gb);
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
        ticks += GB_run(gb);
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
        ticks += GB_run(instance->gb);
    }
    return (SBFrameView){
        .width = SB_WIDTH,
        .height = SB_HEIGHT,
        .pixels = instance->pixels,
        .emulated_nanoseconds = sb_ticks_to_nanoseconds(instance->gb, ticks),
    };
}

void SBSetColorCorrection(SBInstance *instance, SBColorCorrection mode)
{
    if (!instance || !instance->gb) return;
    GB_color_correction_mode_t correction;
    switch (mode) {
        case SB_COLOR_CORRECTION_OFF: correction = GB_COLOR_CORRECTION_DISABLED; break;
        case SB_COLOR_CORRECTION_ACCURATE: correction = GB_COLOR_CORRECTION_MODERN_ACCURATE; break;
        case SB_COLOR_CORRECTION_BALANCED: correction = GB_COLOR_CORRECTION_MODERN_BALANCED; break;
        case SB_COLOR_CORRECTION_BOOST_CONTRAST: correction = GB_COLOR_CORRECTION_MODERN_BOOST_CONTRAST; break;
        case SB_COLOR_CORRECTION_REDUCE_CONTRAST: correction = GB_COLOR_CORRECTION_REDUCE_CONTRAST; break;
        case SB_COLOR_CORRECTION_LOW_CONTRAST: correction = GB_COLOR_CORRECTION_LOW_CONTRAST; break;
        default: return;
    }
    GB_set_color_correction_mode(instance->gb, correction);
    sb_apply_dmg_palette(instance);
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
    instance->previewing = true;
    *frame = SBRunFrame(instance);
    instance->previewing = false;
    bool restored = SBLoadState(instance, state, size);
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
