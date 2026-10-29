#include "SameBoyBridge.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void test_camera_rgb(void);
void test_printer(void);
void test_joypad_transitions(void);

static void make_test_rom(uint8_t *rom, size_t size)
{
    memset(rom, 0, size);
    rom[0x100] = 0x18;
    rom[0x101] = 0xfe;
    memcpy(&rom[0x134], "SAMEBOY BRIDGE", 14);
    rom[0x147] = 0x00;
    rom[0x148] = 0x00;
    rom[0x149] = 0x00;
    uint8_t checksum = 0;
    for (size_t i = 0x134; i <= 0x14c; i++) checksum = checksum - rom[i] - 1;
    rom[0x14d] = checksum;
}

// Boot ROM stubs. The finishing one ends like a real boot ROM: it unmaps itself by writing FF50 from
// $00FC, so execution continues at the cartridge's $0100.
static void make_finishing_boot_rom(uint8_t *boot)
{
    memset(boot, 0, 256);
    boot[0x00] = 0xc3; boot[0x01] = 0xfc; boot[0x02] = 0x00; // jp $00FC
    boot[0xfc] = 0x3e; boot[0xfd] = 0x01;                    // ld a, 1
    boot[0xfe] = 0xe0; boot[0xff] = 0x50;                    // ldh [$FF50], a
}

static void make_endless_boot_rom(uint8_t *boot)
{
    memset(boot, 0, 256);
    boot[0x00] = 0x18; boot[0x01] = 0xfe; // jr @
}

// Every model draws a 160x144 picture, Super Game Boys included, and keeps states.
static void test_every_model(const uint8_t *rom, size_t rom_size)
{
    const SBModel models[] = {
        SB_MODEL_DMG, SB_MODEL_MGB, SB_MODEL_SGB, SB_MODEL_SGB2, SB_MODEL_CGB, SB_MODEL_AGB, SB_MODEL_GBP,
    };
    uint8_t finishing[256];
    make_finishing_boot_rom(finishing);
    for (size_t i = 0; i < sizeof(models) / sizeof(models[0]); i++) {
        SBInstance *instance = SBCreate(models[i]);
        assert(instance);
        assert(SBLoadBootROM(instance, finishing, sizeof(finishing)));
        assert(SBLoadROM(instance, rom, rom_size));
        assert(SBSkipBootROM(instance, NULL, 0));
        // Game Boy Advance models color each frame into their own buffer; the rest ignore it.
        SBSetGBCColorsOnAGB(instance, true);
        SBSetColorCorrection(instance, SB_COLOR_CORRECTION_ACCURATE);
        for (int frame_index = 0; frame_index < 120; frame_index++) {
            SBFrameView frame = SBRunFrame(instance);
            assert(frame.width == 160 && frame.height == 144 && frame.pixels);
        }
        size_t state_size = SBStateSize(instance);
        uint8_t *state = malloc(state_size);
        assert(state);
        assert(SBSaveState(instance, state, state_size));
        assert(SBLoadState(instance, state, state_size));
        free(state);
        SBDestroy(instance);
    }
}

static void test_boot_skip(const uint8_t *rom, size_t rom_size)
{
    uint8_t finishing[256], endless[256];
    make_finishing_boot_rom(finishing);
    make_endless_boot_rom(endless);

    // A boot ROM that hands off is run to completion.
    SBInstance *instance = SBCreate(SB_MODEL_DMG);
    assert(instance);
    assert(SBLoadBootROM(instance, finishing, sizeof(finishing)));
    assert(SBLoadROM(instance, rom, rom_size));
    assert(SBSkipBootROM(instance, NULL, 0));
    SBStereoSample samples[16];
    assert(SBDrainAudio(instance, samples, 16) == 0);
    SBDestroy(instance);

    // Before anything runs, the fast variant replaces the loaded boot ROM.
    instance = SBCreate(SB_MODEL_DMG);
    assert(SBLoadBootROM(instance, endless, sizeof(endless)));
    assert(SBLoadROM(instance, rom, rom_size));
    assert(SBSkipBootROM(instance, finishing, sizeof(finishing)));
    SBDestroy(instance);

    // Once a frame has run, the loaded boot ROM stays, and one that never hands off is bounded.
    instance = SBCreate(SB_MODEL_DMG);
    assert(SBLoadBootROM(instance, endless, sizeof(endless)));
    assert(SBLoadROM(instance, rom, rom_size));
    (void)SBRunFrame(instance);
    assert(!SBSkipBootROM(instance, finishing, sizeof(finishing)));
    SBDestroy(instance);
}

// An MBC5+Rumble cartridge (type $1C) whose program turns the motor on: bit 3 of the ROM bank
// register at $4000 drives it.
static void test_cartridge_rumble(void)
{
    static uint8_t rom[32768];
    memset(rom, 0, sizeof(rom));
    const uint8_t program[] = {
        0x3e, 0x08,       // ld a, $08
        0xea, 0x00, 0x40, // ld [$4000], a
        0x18, 0xfe,       // jr @
    };
    memcpy(&rom[0x100], program, sizeof(program));
    memcpy(&rom[0x134], "RUMBLE", 6);
    rom[0x147] = 0x1c;
    uint8_t checksum = 0;
    for (size_t i = 0x134; i <= 0x14c; i++) checksum = checksum - rom[i] - 1;
    rom[0x14d] = checksum;

    uint8_t boot[256] = {0};
    boot[0] = 0xc3; boot[1] = 0x00; boot[2] = 0x01; // jp $0100

    SBInstance *instance = SBCreate(SB_MODEL_DMG);
    assert(SBLoadBootROM(instance, boot, sizeof(boot)));
    assert(SBLoadROM(instance, rom, sizeof(rom)));
    (void)SBRunFrame(instance);
    assert(SBConsumeRumbleAmplitude(instance) > 0);
    SBDestroy(instance);
}

// An MBC7 cartridge (type $22) reads tilt; an ordinary one doesn't, and setting tilt on it is
// harmless.
static void test_tilt_cartridge(void)
{
    static uint8_t rom[65536];
    memset(rom, 0, sizeof(rom));
    rom[0x100] = 0x18;
    rom[0x101] = 0xfe;
    memcpy(&rom[0x134], "TILT", 4);
    rom[0x147] = 0x22;
    rom[0x148] = 0x01;
    uint8_t checksum = 0;
    for (size_t i = 0x134; i <= 0x14c; i++) checksum = checksum - rom[i] - 1;
    rom[0x14d] = checksum;
    uint8_t boot[256] = {0};
    boot[0] = 0xc3; boot[1] = 0x00; boot[2] = 0x01; // jp $0100

    SBInstance *instance = SBCreate(SB_MODEL_DMG);
    assert(SBLoadBootROM(instance, boot, sizeof(boot)));
    assert(SBLoadROM(instance, rom, sizeof(rom)));
    assert(SBHasAccelerometer(instance));
    SBSetAccelerometer(instance, 0.5, -0.25);
    (void)SBRunFrame(instance);
    SBDestroy(instance);

    rom[0x147] = 0x00;
    instance = SBCreate(SB_MODEL_DMG);
    assert(SBLoadBootROM(instance, boot, sizeof(boot)));
    assert(SBLoadROM(instance, rom, sizeof(rom)));
    assert(!SBHasAccelerometer(instance));
    SBSetAccelerometer(instance, 1, 1);
    SBDestroy(instance);
}

// A save one byte longer than the cartridge's 8 KiB of RAM. SameBoy reads an RTC trailer's worth
// of bytes after the RAM whatever the file's length, so this catches a read past the caller's
// buffer when built with AddressSanitizer.
static void test_oversized_battery(void)
{
    static uint8_t rom[32768];
    make_test_rom(rom, sizeof(rom));
    rom[0x147] = 0x03; // MBC1+RAM+BATTERY
    rom[0x149] = 0x02; // 8 KiB

    uint8_t boot[256] = {0};
    boot[0] = 0xc3; boot[1] = 0x00; boot[2] = 0x01; // jp $0100

    SBInstance *instance = SBCreate(SB_MODEL_DMG);
    assert(SBLoadBootROM(instance, boot, sizeof(boot)));
    assert(SBLoadROM(instance, rom, sizeof(rom)));
    assert(SBBatterySize(instance) == 0x2000);

    size_t size = 0x2001;
    uint8_t *save = malloc(size);
    assert(save);
    memset(save, 0x41, size);
    SBLoadBattery(instance, save, size);
    free(save);

    uint8_t *loaded = malloc(0x2000);
    assert(loaded);
    assert(SBSaveBattery(instance, loaded, 0x2000));
    for (size_t i = 0; i < 0x2000; i++) assert(loaded[i] == 0x41);
    free(loaded);
    SBDestroy(instance);
}

// The largest cartridge image loads, and one byte more is refused before SameBoy allocates for it.
static void test_rom_size_limit(void)
{
    size_t largest = 8u * 1024u * 1024u;
    uint8_t *rom = malloc(largest + 1);
    assert(rom);
    make_test_rom(rom, largest + 1);

    uint8_t boot[256] = {0};
    boot[0] = 0xc3; boot[1] = 0x00; boot[2] = 0x01; // jp $0100

    SBInstance *instance = SBCreate(SB_MODEL_DMG);
    assert(SBLoadBootROM(instance, boot, sizeof(boot)));
    assert(SBLoadROM(instance, rom, largest));
    assert(!SBLoadROM(instance, rom, largest + 1));
    free(rom);
    SBDestroy(instance);
}

// Replacing, refusing and clearing cheats, which builds and frees SameBoy's cheat lists. Built with
// AddressSanitizer, this also catches a cheat freed twice or left behind.
static void test_cheats(const uint8_t *rom, size_t rom_size)
{
    uint8_t boot[256] = {0};
    boot[0] = 0xc3; boot[1] = 0x00; boot[2] = 0x01; // jp $0100

    assert(SBCheckCheat("014200C0"));
    assert(SBCheckCheat("990-00B-EFA"));
    assert(!SBCheckCheat("123-456"));
    assert(!SBCheckCheat("+14200C0"));
    assert(!SBCheckCheat(NULL));

    SBInstance *instance = SBCreate(SB_MODEL_DMG);
    assert(SBLoadBootROM(instance, boot, sizeof(boot)));
    assert(SBLoadROM(instance, rom, rom_size));
    const char *both[] = {"014200C0", "990-00B"};
    const char *one[] = {"990-00B-EFA"};
    const char *refused[] = {"014300C0", "123-456"};
    SBSetCheatsEnabled(instance, true);
    assert(SBSetCheats(instance, both, 2));
    assert(SBSetCheats(instance, one, 1));
    assert(!SBSetCheats(instance, refused, 2));
    (void)SBRunFrame(instance);
    assert(SBSetCheats(instance, NULL, 0));
    assert(SBSetCheats(instance, both, 2));
    SBDestroy(instance);
}

// A synthetic camera cartridge exposes its first sensor tile in WRAM. It waits for the
// camera's busy bit before reading, so a missing completion leaves the marker unset.
static void test_camera(void)
{
    uint8_t rom[32768];
    make_test_rom(rom, sizeof(rom));
    rom[0x147] = 0xfc;
    rom[0x149] = 0x04;
    rom[0x100] = 0xc3; rom[0x101] = 0x50; rom[0x102] = 0x01;
    const uint8_t setup[] = {
        0x3e, 0x0a, 0xea, 0x00, 0x00, // enable RAM
        0x3e, 0x10, 0xea, 0x00, 0x40, // camera registers
        0x3e, 0x04, 0xea, 0x01, 0xa0, // unit gain
        0x3e, 0x10, 0xea, 0x02, 0xa0, // exposure $1000
        0xaf, 0xea, 0x03, 0xa0,
    };
    size_t pc = 0x150;
    memcpy(rom + pc, setup, sizeof(setup)); pc += sizeof(setup);
    for (unsigned i = 0; i < 48; i++) {
        const uint8_t threshold[] = {0x3e, (uint8_t)(64 * (i % 3 + 1)), 0xea, (uint8_t)(6 + i), 0xa0};
        memcpy(rom + pc, threshold, sizeof(threshold)); pc += sizeof(threshold);
    }
    const uint8_t shoot[] = {
        0x3e, 0x01, 0xea, 0x00, 0xa0,
        0xfa, 0x00, 0xa0, 0xe6, 0x01, 0x20, 0xf9, // wait for sensor
        0xaf, 0xea, 0x00, 0x40, // RAM bank 0
        0xfa, 0x00, 0xa1, 0xea, 0x00, 0xc0,
        0xfa, 0x01, 0xa1, 0xea, 0x01, 0xc0,
        0x3e, 0x01, 0xea, 0x00, 0x40, // save the tile in battery RAM bank 1
        0xfa, 0x00, 0xc0, 0xea, 0x00, 0xa0,
        0xfa, 0x01, 0xc0, 0xea, 0x01, 0xa0,
        0xaf, 0xea, 0x00, 0x40, // return to the sensor image
        0x3e, 0x42, 0xea, 0x02, 0xc0,
        0x18, 0xfe,
    };
    memcpy(rom + pc, shoot, sizeof(shoot));
    uint8_t boot[256];
    make_finishing_boot_rom(boot);
    SBInstance *instance = SBCreate(SB_MODEL_DMG);
    assert(!SBHasCamera(instance));
    assert(SBLoadBootROM(instance, boot, sizeof(boot)));
    assert(SBLoadROM(instance, rom, sizeof(rom)));
    assert(SBHasCamera(instance));
    uint8_t sensor[128 * 112];
    const uint8_t values[] = {255, 0, 128};
    const uint8_t low[] = {0x00, 0xff, 0xff};
    const uint8_t high[] = {0x00, 0xff, 0x00};
    for (unsigned test = 0; test < 3; test++) {
        SBReset(instance);
        assert(SBSkipBootROM(instance, NULL, 0));
        memset(sensor, test == 2 ? 0 : values[test], sizeof(sensor));
        assert(SBSetCameraFrame(instance, sensor, sizeof(sensor)));
        assert(!SBSetCameraFrame(instance, sensor, sizeof(sensor) - 1));
        assert(!SBSetCameraFrame(instance, sensor, sizeof(sensor) + 1));
        if (test == 2) assert(SBSetCameraFrame(instance, NULL, 0));
        size_t state_size = SBStateSize(instance);
        uint8_t *before_shot = malloc(state_size);
        uint8_t *after_shot = malloc(state_size);
        assert(before_shot && after_shot);
        assert(SBSaveState(instance, before_shot, state_size));
        (void)SBRunFrame(instance);
        (void)SBRunFrame(instance);
        assert(SBReadMemory(instance, 0xc002) == 0x42);
        assert(SBReadMemory(instance, 0xc000) == low[test]);
        assert(SBReadMemory(instance, 0xc001) == high[test]);
        // The exposed image belongs to that shot, even when a new sensor frame arrives.
        memset(sensor, 255 - values[test], sizeof(sensor));
        assert(SBSetCameraFrame(instance, sensor, sizeof(sensor)));
        assert(SBReadMemory(instance, 0xa100) == low[test]);
        assert(SBReadMemory(instance, 0xa101) == high[test]);
        assert(SBSaveState(instance, after_shot, state_size));
        assert(SBLoadState(instance, before_shot, state_size));
        SBFrameView preview;
        assert(SBRefreshFrame(instance, &preview));
        assert(preview.emulated_nanoseconds == 0);
        assert(SBLoadState(instance, after_shot, state_size));
        assert(SBReadMemory(instance, 0xa100) == low[test]);
        assert(SBReadMemory(instance, 0xa101) == high[test]);
        free(before_shot);
        free(after_shot);
        size_t size = SBBatterySize(instance);
        assert(size > 0x2001);
        uint8_t *battery = malloc(size);
        assert(battery && SBSaveBattery(instance, battery, size));
        assert(battery[0x2000] == low[test] && battery[0x2001] == high[test]);
        SBInstance *restored = SBCreate(SB_MODEL_DMG);
        assert(SBLoadROM(restored, rom, sizeof(rom)));
        SBLoadBattery(restored, battery, size);
        memset(battery, 0, size);
        assert(SBSaveBattery(restored, battery, size));
        assert(battery[0x2000] == low[test] && battery[0x2001] == high[test]);
        free(battery);
        SBDestroy(restored);
    }
    assert(SBLoadROM(instance, rom, sizeof(rom)));
    SBDestroy(instance);
}

int main(void)
{
    SBInstance *instance = SBCreate(SB_MODEL_DMG);
    assert(instance);

    uint8_t boot[256] = {0};
    boot[0] = 0xc3;
    boot[1] = 0x00;
    boot[2] = 0x01;
    assert(SBLoadBootROM(instance, boot, sizeof(boot)));

    uint8_t rom[32768];
    make_test_rom(rom, sizeof(rom));
    assert(SBLoadROM(instance, rom, sizeof(rom)));

    SBFrameView frame = SBRunFrame(instance);
    assert(frame.width == 160);
    assert(frame.height == 144);
    assert(frame.pixels != NULL);
    // One DMG frame is 70224 cycles at 4194304 Hz, about 16.74 ms; GameplayDriver paces by this.
    assert(frame.emulated_nanoseconds > 16700000u && frame.emulated_nanoseconds < 16800000u);

    size_t state_size = SBStateSize(instance);
    assert(state_size > 0);
    uint8_t *state = malloc(state_size);
    assert(state);
    assert(SBSaveState(instance, state, state_size));
    (void)SBRunFrame(instance);
    assert(SBLoadState(instance, state, state_size));

    free(state);
    SBDestroy(instance);

    test_boot_skip(rom, sizeof(rom));
    test_every_model(rom, sizeof(rom));
    test_cartridge_rumble();
    test_tilt_cartridge();
    test_oversized_battery();
    test_rom_size_limit();
    test_cheats(rom, sizeof(rom));
    test_camera();
    test_camera_rgb();
    test_printer();
    test_joypad_transitions();
    puts("sameboy bridge smoke: ok");
    return 0;
}
