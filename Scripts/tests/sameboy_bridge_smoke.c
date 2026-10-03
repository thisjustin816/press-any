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
    puts("sameboy bridge smoke: ok");
    return 0;
}
