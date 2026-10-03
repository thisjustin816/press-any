#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SBInstance SBInstance;

typedef enum {
    SB_MODEL_DMG,
    SB_MODEL_CGB,
} SBModel;

typedef struct {
    bool up;
    bool down;
    bool left;
    bool right;
    bool a;
    bool b;
    bool start;
    bool select;
} SBInputState;

typedef struct {
    uint32_t width;
    uint32_t height;
    const uint32_t *pixels;
    uint64_t emulated_nanoseconds;
} SBFrameView;

typedef struct {
    int16_t left;
    int16_t right;
} SBStereoSample;

SBInstance *SBCreate(SBModel model);
void SBDestroy(SBInstance *instance);

bool SBLoadBootROM(SBInstance *instance, const uint8_t *bytes, size_t size);
bool SBLoadROM(SBInstance *instance, const uint8_t *bytes, size_t size);
/// Runs the boot ROM to its hand-off without drawing it and drops its audio, so the game starts in the
/// state the boot ROM leaves it, minus the logo. If nothing has run since the image was loaded,
/// fast_boot_rom (optional) replaces the loaded boot ROM first: a variant that reaches the same
/// hand-off without the animation, such as SameBoy's cgb_boot_fast. Returns false if the boot ROM
/// did not finish within a bounded amount of emulated time.
bool SBSkipBootROM(SBInstance *instance, const uint8_t *fast_boot_rom, size_t fast_boot_rom_size);

void SBSetInput(SBInstance *instance, SBInputState input);
SBFrameView SBRunFrame(SBInstance *instance);
size_t SBDrainAudio(SBInstance *instance, SBStereoSample *output, size_t max_frames);
double SBConsumeRumbleAmplitude(SBInstance *instance);

size_t SBBatterySize(SBInstance *instance);
bool SBSaveBattery(SBInstance *instance, uint8_t *output, size_t size);
void SBLoadBattery(SBInstance *instance, const uint8_t *bytes, size_t size);

size_t SBStateSize(SBInstance *instance);
bool SBSaveState(SBInstance *instance, uint8_t *output, size_t size);
bool SBLoadState(SBInstance *instance, const uint8_t *bytes, size_t size);

void SBReset(SBInstance *instance);

#ifdef __cplusplus
}
#endif
