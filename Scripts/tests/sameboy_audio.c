#include "SameBoyBridge.h"
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// A game that leaves a channel's DAC on at volume 0 and routed to the speakers holds a constant
// level at the output. Hardware's output capacitor removes it; without a high-pass filter it
// reaches the speakers, and every gap in playback steps between it and silence as a click. The
// ROM switches the APU on, routes channel 1 to both sides at full master volume, triggers it with
// its DAC on at volume 0 and no envelope, and halts.
static void make_idle_dac_rom(uint8_t *rom, size_t size)
{
    memset(rom, 0, size);
    rom[0x100] = 0xc3; rom[0x101] = 0x50; rom[0x102] = 0x01; // jp $0150
    memcpy(&rom[0x134], "IDLEDAC", 7);
    uint8_t checksum = 0;
    for (size_t i = 0x134; i <= 0x14c; i++) checksum = checksum - rom[i] - 1;
    rom[0x14d] = checksum;
    const uint8_t code[] = {
        0x3e, 0x80, 0xe0, 0x26, // ld a, $80 ; ldh [NR52], a (APU on)
        0x3e, 0x77, 0xe0, 0x24, // ld a, $77 ; ldh [NR50], a (master volume)
        0x3e, 0x11, 0xe0, 0x25, // ld a, $11 ; ldh [NR51], a (channel 1 left and right)
        0x3e, 0x08, 0xe0, 0x12, // ld a, $08 ; ldh [NR12], a (DAC on, volume 0, no envelope)
        0x3e, 0x80, 0xe0, 0x14, // ld a, $80 ; ldh [NR14], a (trigger)
        0xf3,                   // di
        0x76, 0x00,             // halt ; nop
        0x18, 0xfc,             // jr halt
    };
    memcpy(&rom[0x150], code, sizeof(code));
}

typedef struct {
    double mean_left;
    double mean_right;
} audio_level;

static SBStereoSample *drain_buffer;
#define DRAIN_CAPACITY 8192

// Runs `frames` frames, keeping only the last frame's samples, and returns their mean level.
static audio_level run_frames(SBInstance *instance, int frames)
{
    size_t count = 0;
    for (int f = 0; f < frames; f++) {
        (void)SBRunFrame(instance);
        count = SBDrainAudio(instance, drain_buffer, DRAIN_CAPACITY);
    }
    assert(count > 0);
    double left = 0, right = 0;
    for (size_t i = 0; i < count; i++) {
        left += drain_buffer[i].left;
        right += drain_buffer[i].right;
    }
    return (audio_level){left / count, right / count};
}

static SBInstance *start(SBModel model, const uint8_t *rom, size_t size)
{
    SBInstance *instance = SBCreate(model);
    assert(instance);
    uint8_t boot[256] = {0};
    boot[0] = 0xc3; boot[1] = 0x00; boot[2] = 0x01; // jp $0100
    assert(SBLoadBootROM(instance, boot, sizeof(boot)));
    assert(SBLoadROM(instance, rom, size));
    return instance;
}

// A level this close to zero is silence to the ear; the idle offset is thousands.
#define SILENT 64.0
#define OFFSET 1000.0

static void expect_offset(audio_level level, const char *what)
{
    fprintf(stderr, "%s: mean %.1f / %.1f\n", what, level.mean_left, level.mean_right);
    assert(level.mean_left > OFFSET && level.mean_right > OFFSET);
}

static void expect_silent(audio_level level, const char *what)
{
    fprintf(stderr, "%s: mean %.1f / %.1f\n", what, level.mean_left, level.mean_right);
    assert(level.mean_left > -SILENT && level.mean_left < SILENT);
    assert(level.mean_right > -SILENT && level.mean_right < SILENT);
}

void test_audio_highpass(void)
{
    drain_buffer = malloc(sizeof(*drain_buffer) * DRAIN_CAPACITY);
    assert(drain_buffer);
    uint8_t rom[32768];
    make_idle_dac_rom(rom, sizeof(rom));

    const SBModel models[] = { SB_MODEL_DMG, SB_MODEL_CGB, SB_MODEL_AGB };
    for (size_t m = 0; m < sizeof(models) / sizeof(models[0]); m++) {
        SBInstance *instance = start(models[m], rom, sizeof(rom));
        // Within one second of play the default filter has removed the idle level.
        expect_silent(run_frames(instance, 60), "default after 1 s");

        // Off leaves the idle level in place; it stays Off through a reset and a state load.
        SBSetHighpassFilter(instance, SB_HIGHPASS_OFF);
        expect_offset(run_frames(instance, 30), "off");
        SBReset(instance);
        expect_offset(run_frames(instance, 60), "off after reset");
        size_t state_size = SBStateSize(instance);
        uint8_t *state = malloc(state_size);
        assert(state && SBSaveState(instance, state, state_size));
        (void)run_frames(instance, 5);
        assert(SBLoadState(instance, state, state_size));
        expect_offset(run_frames(instance, 30), "off after state load");
        free(state);

        SBSetHighpassFilter(instance, SB_HIGHPASS_ACCURATE);
        expect_silent(run_frames(instance, 60), "accurate");
        SBDestroy(instance);
    }
    free(drain_buffer);
}
