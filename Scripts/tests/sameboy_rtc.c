#include "SameBoyBridge.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

// An MBC3 cartridge's clock keeps real time on its own battery, so it runs on while the game is
// paused, in the background or closed, and loading a state rewinds the Game Boy but not the clock.
// A clock the game halts stays where it is until the game starts it again. The ROM latches the
// clock in a loop and copies seconds, minutes and the high register to WRAM; when the byte at
// $0140 is set, it halts the clock first.
#define RTC_SECONDS 0xc000u
#define RTC_MINUTES 0xc001u
#define RTC_HIGH 0xc002u

static void make_rtc_rom(uint8_t *rom, size_t size, bool halt)
{
    memset(rom, 0, size);
    rom[0x100] = 0xc3; rom[0x101] = 0x50; rom[0x102] = 0x01;
    memcpy(&rom[0x134], "RTCCLOCK", 8);
    rom[0x140] = halt;
    rom[0x147] = 0x10; // MBC3+TIMER+RAM+BATTERY
    rom[0x148] = 0x00;
    rom[0x149] = 0x03; // 32 KB
    uint8_t checksum = 0;
    for (size_t i = 0x134; i <= 0x14c; i++) checksum = checksum - rom[i] - 1;
    rom[0x14d] = checksum;
    const uint8_t code[] = {
        0x3e, 0x0a, 0xea, 0x00, 0x00,       // ld a, $0A ; ld [$0000], a (RAM and clock on)
        0xfa, 0x40, 0x01, 0xb7, 0x28, 0x0a, // ld a, [$0140] ; or a ; jr z, loop
        0x3e, 0x0c, 0xea, 0x00, 0x40,       // ld a, $0C ; ld [$4000], a (DH)
        0x3e, 0x40, 0xea, 0x00, 0xa0,       // ld a, $40 ; ld [$A000], a (halt)
        // loop:
        0xaf, 0xea, 0x00, 0x60,             // xor a ; ld [$6000], a
        0x3e, 0x01, 0xea, 0x00, 0x60,       // ld a, 1 ; ld [$6000], a (latch)
        0x3e, 0x08, 0xea, 0x00, 0x40,       // ld a, $08 ; ld [$4000], a
        0xfa, 0x00, 0xa0, 0xea, 0x00, 0xc0, // ld a, [$A000] ; ld [$C000], a
        0x3e, 0x09, 0xea, 0x00, 0x40,       // ld a, $09 ; ld [$4000], a
        0xfa, 0x00, 0xa0, 0xea, 0x01, 0xc0, // ld a, [$A000] ; ld [$C001], a
        0x3e, 0x0c, 0xea, 0x00, 0x40,       // ld a, $0C ; ld [$4000], a
        0xfa, 0x00, 0xa0, 0xea, 0x02, 0xc0, // ld a, [$A000] ; ld [$C002], a
        0x18, 0xd4,                         // jr loop
    };
    memcpy(&rom[0x150], code, sizeof(code));
}

static SBInstance *start(const uint8_t *rom, size_t size)
{
    SBInstance *instance = SBCreate(SB_MODEL_DMG);
    assert(instance);
    uint8_t boot[256] = {0xc3, 0x00, 0x01}; // jp $0100
    assert(SBLoadBootROM(instance, boot, sizeof(boot)));
    assert(SBLoadROM(instance, rom, size));
    return instance;
}

// The clock as the game last latched it, in seconds, after a few frames of play.
static unsigned clock_seconds(SBInstance *instance)
{
    for (int i = 0; i < 10; i++) (void)SBRunFrame(instance);
    return SBReadMemory(instance, RTC_MINUTES) * 60u + SBReadMemory(instance, RTC_SECONDS);
}

// The host clock counts whole seconds, so a span of `seconds` reads as that, give or take one.
static void expect_advance(unsigned before, unsigned after, int seconds, const char *what)
{
    int advance = (int)after - (int)before;
    fprintf(stderr, "rtc %s: %u -> %u (%+d s, expected %+d)\n", what, before, after, advance, seconds);
    assert(advance >= seconds - 1 && advance <= seconds + 1);
}

static void run_for_real_seconds(SBInstance *instance, unsigned seconds)
{
    time_t end = time(NULL) + seconds;
    while (time(NULL) < end) (void)SBRunFrame(instance);
}

static void check_clock(bool halted)
{
    uint8_t rom[32768];
    make_rtc_rom(rom, sizeof(rom), halted);
    const int span = halted ? 0 : 2;
    SBInstance *instance = start(rom, sizeof(rom));
    unsigned first = clock_seconds(instance);
    assert(((SBReadMemory(instance, RTC_HIGH) & 0x40) != 0) == halted);

    run_for_real_seconds(instance, 2);
    unsigned after_play = clock_seconds(instance);
    expect_advance(first, after_play, span, halted ? "halted, playing" : "playing");

    // Paused or in the background: no frames run.
    sleep(2);
    unsigned after_pause = clock_seconds(instance);
    expect_advance(after_play, after_pause, span, halted ? "halted, paused" : "paused");

    // A state, then two seconds of play, then loading the state.
    size_t state_size = SBStateSize(instance);
    uint8_t *state = malloc(state_size);
    assert(state && SBSaveState(instance, state, state_size));
    unsigned at_save = clock_seconds(instance);
    run_for_real_seconds(instance, 2);
    assert(SBLoadState(instance, state, state_size));
    free(state);
    unsigned after_load = clock_seconds(instance);
    expect_advance(at_save, after_load, span, halted ? "halted, state loaded" : "state loaded");

    // Closed with its battery saved, then opened two seconds later.
    size_t battery_size = SBBatterySize(instance);
    uint8_t *battery = malloc(battery_size);
    assert(battery && SBSaveBattery(instance, battery, battery_size));
    unsigned at_close = clock_seconds(instance);
    SBDestroy(instance);
    sleep(2);
    instance = start(rom, sizeof(rom));
    SBLoadBattery(instance, battery, battery_size);
    free(battery);
    unsigned after_relaunch = clock_seconds(instance);
    expect_advance(at_close, after_relaunch, span, halted ? "halted, relaunched" : "relaunched");
    SBDestroy(instance);
}

void test_rtc(void)
{
    check_clock(false);
    check_clock(true);
}
