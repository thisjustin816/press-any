#include "SameBoyBridge.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
    test_cartridge_rumble();
    test_oversized_battery();
    test_rom_size_limit();
    test_cheats(rom, sizeof(rom));
    puts("sameboy bridge smoke: ok");
    return 0;
}
