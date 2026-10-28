#include "SameBoyBridge.h"
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

// A press or release set before a frame reaches the game as one transition, with no contact
// bounce: a game that samples the joypad more than once per frame must not see a key change
// twice. The ROM selects the direction keys, reads FF00 in a tight loop, and counts each read
// that differs from the previous one in C000.
static void make_joypad_rom(uint8_t *rom, size_t size)
{
    memset(rom, 0, size);
    rom[0x100] = 0xc3; rom[0x101] = 0x50; rom[0x102] = 0x01; // jp $0150
    memcpy(&rom[0x134], "JOYPAD", 6);
    uint8_t checksum = 0;
    for (size_t i = 0x134; i <= 0x14c; i++) checksum = checksum - rom[i] - 1;
    rom[0x14d] = checksum;
    const uint8_t code[] = {
        0x3e, 0x20, 0xe0, 0x00,             // ld a, $20 ; ldh [JOYP], a  (select directions)
        0xaf, 0xea, 0x00, 0xc0,             // xor a ; ld [$C000], a      (transition count)
        0xf0, 0x00, 0xe6, 0x0f, 0x47,       // ldh a, [JOYP] ; and $0F ; ld b, a (last value)
        // loop:
        0xf0, 0x00, 0xe6, 0x0f,             // ldh a, [JOYP] ; and $0F
        0xb8, 0x28, 0x08,                   // cp b ; jr z, same (skips the next 8 bytes)
        0x47, 0xfa, 0x00, 0xc0, 0x3c,       // ld b, a ; ld a, [$C000] ; inc a
        0xea, 0x00, 0xc0,                   // ld [$C000], a
        // same:
        0x18, 0xef,                         // jr loop (17 bytes back)
    };
    memcpy(&rom[0x150], code, sizeof(code));
}

void test_joypad_transitions(void)
{
    uint8_t rom[32768];
    make_joypad_rom(rom, sizeof(rom));
    const SBModel models[] = { SB_MODEL_DMG, SB_MODEL_CGB };
    for (size_t m = 0; m < sizeof(models) / sizeof(models[0]); m++) {
        SBInstance *instance = SBCreate(models[m]);
        assert(instance);
        uint8_t boot[256] = {0};
        boot[0] = 0xc3; boot[1] = 0x00; boot[2] = 0x01; // jp $0100
        assert(SBLoadBootROM(instance, boot, sizeof(boot)));
        assert(SBLoadROM(instance, rom, sizeof(rom)));
        SBInputState none = {0}, down = {0};
        down.down = true;
        for (int i = 0; i < 10; i++) { SBSetInput(instance, none); (void)SBRunFrame(instance); }
        uint8_t before = SBReadMemory(instance, 0xc000);
        // 40 taps of 3 to 5 frames: every press and every release is exactly one transition.
        for (int tap = 0; tap < 40; tap++) {
            int held = 3 + tap % 3;
            for (int f = 0; f < held; f++) { SBSetInput(instance, down); (void)SBRunFrame(instance); }
            for (int f = 0; f < 17 + tap % 4; f++) { SBSetInput(instance, none); (void)SBRunFrame(instance); }
        }
        uint8_t transitions = (uint8_t)(SBReadMemory(instance, 0xc000) - before);
        fprintf(stderr, "model %d: %u transitions for 40 taps (80 expected)\n", (int)models[m], transitions);
        assert(transitions == 80);
        SBDestroy(instance);
    }
}
