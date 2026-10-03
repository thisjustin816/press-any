#include "SameBoyBridge.h"

#if __has_include(<sameboy/gb.h>)
#include <sameboy/gb.h>
#else
#include "gb.h"
#endif

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

struct SBInstance {
    GB_gameboy_t *gb;
    uint32_t *pixels;
    SBStereoSample audio[SB_AUDIO_CAPACITY];
    _Atomic size_t audio_read;
    _Atomic size_t audio_write;
    _Atomic uint64_t rumble_bits;
    bool vblank;
    bool has_run; // Whether any emulation has run since the image was loaded or reset.
};

static uint32_t sb_encode_bgra(GB_gameboy_t *gb, uint8_t r, uint8_t g, uint8_t b)
{
    (void)gb;
    return 0xff000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
}

static void sb_audio_callback(GB_gameboy_t *gb, GB_sample_t *sample)
{
    SBInstance *instance = GB_get_user_data(gb);
    if (!instance || !sample) return;

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
    if (!instance) return;

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
    if (!instance || !instance->gb || !bytes || size < 0x150) return false;
    GB_load_rom_from_buffer(instance->gb, bytes, size);
    GB_reset(instance->gb);
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
    GB_load_battery_from_buffer(instance->gb, bytes, size);
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
    return GB_load_state_from_buffer(instance->gb, bytes, size) == 0;
}

void SBReset(SBInstance *instance)
{
    if (!instance || !instance->gb) return;
    GB_reset(instance->gb);
    instance->has_run = false;
}
