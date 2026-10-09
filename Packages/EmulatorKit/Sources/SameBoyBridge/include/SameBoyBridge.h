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

typedef enum {
    SB_COLOR_CORRECTION_OFF,
    SB_COLOR_CORRECTION_ACCURATE,
    SB_COLOR_CORRECTION_BALANCED,
    SB_COLOR_CORRECTION_BOOST_CONTRAST,
    SB_COLOR_CORRECTION_REDUCE_CONTRAST,
    SB_COLOR_CORRECTION_LOW_CONTRAST,
} SBColorCorrection;

typedef enum {
    SB_DMG_PALETTE_GREY,
    SB_DMG_PALETTE_DMG,
    SB_DMG_PALETTE_MGB,
    SB_DMG_PALETTE_GBL,
    SB_DMG_PALETTE_CGB_UP,
    SB_DMG_PALETTE_CGB_UP_A,
    SB_DMG_PALETTE_CGB_UP_B,
    SB_DMG_PALETTE_CGB_DOWN,
    SB_DMG_PALETTE_CGB_DOWN_A,
    SB_DMG_PALETTE_CGB_DOWN_B,
    SB_DMG_PALETTE_CGB_LEFT,
    SB_DMG_PALETTE_CGB_LEFT_A,
    SB_DMG_PALETTE_CGB_LEFT_B,
    SB_DMG_PALETTE_CGB_RIGHT,
    SB_DMG_PALETTE_CGB_RIGHT_A,
    SB_DMG_PALETTE_CGB_RIGHT_B,
    SB_DMG_PALETTE_CGB_OLIVE,
} SBDMGPalette;

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

typedef struct {
    uint8_t a, f, b, c, d, e, h, l;
    uint16_t sp, pc;
} SBRegisters;

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
void SBSetColorCorrection(SBInstance *instance, SBColorCorrection mode);
/// Changes only DMG render colors, including separate BG/OBJ0/OBJ1 boot palettes.
/// CGB hardware ignores this setting. Emulated palette RAM and state bytes are unchanged.
void SBSetDMGPalette(SBInstance *instance, SBDMGPalette palette);
/// Renders a temporary frame, restoring gameplay state and suppressing audio and rumble.
bool SBRefreshFrame(SBInstance *instance, SBFrameView *frame);
size_t SBDrainAudio(SBInstance *instance, SBStereoSample *output, size_t max_frames);
double SBConsumeRumbleAmplitude(SBInstance *instance);

size_t SBBatterySize(SBInstance *instance);
bool SBSaveBattery(SBInstance *instance, uint8_t *output, size_t size);
void SBLoadBattery(SBInstance *instance, const uint8_t *bytes, size_t size);

size_t SBStateSize(SBInstance *instance);
bool SBSaveState(SBInstance *instance, uint8_t *output, size_t size);
bool SBLoadState(SBInstance *instance, const uint8_t *bytes, size_t size);

void SBReset(SBInstance *instance);

/// Whether SameBoy reads code as a Game Genie (XXX-XXX or XXX-XXX-XXX) or GameShark (01VVAAAA)
/// code. Needs no instance and applies nothing.
bool SBCheckCheat(const char *code);
/// Replaces every cheat with these codes. If any code doesn't read, nothing changes and this
/// returns false.
bool SBSetCheats(SBInstance *instance, const char *const *codes, size_t count);
/// Turns the cheats on or off as a whole, keeping them.
void SBSetCheatsEnabled(SBInstance *instance, bool enabled);

/// For the accuracy harness: test ROMs report their results in CPU registers (Mooneye, SameSuite),
/// as text sent out of the serial port with no link partner, or in cartridge RAM (Blargg).
SBRegisters SBReadRegisters(SBInstance *instance);
/// Reads the byte the CPU would see at addr, without side effects.
uint8_t SBReadMemory(SBInstance *instance, uint16_t addr);
void SBCaptureSerial(SBInstance *instance, bool enabled);
size_t SBDrainSerial(SBInstance *instance, uint8_t *output, size_t max_bytes);

#ifdef __cplusplus
}
#endif
