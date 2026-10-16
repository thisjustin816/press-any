#include "SameBoyBridge.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>

#define SENSOR_SIZE (128u * 112u)

static void emit_write(uint8_t *rom, size_t *pc, uint16_t address, uint8_t value)
{
    uint8_t code[] = {0x3e, value, 0xea, address & 255, address >> 8};
    memcpy(rom + *pc, code, sizeof(code));
    *pc += sizeof(code);
}

// The host sets a command in disposable cartridge RAM. The ROM consumes it, takes one shot,
// and places its first tile bytes beside the handshake so the host can inspect both.
static SBInstance *make_camera(void)
{
    uint8_t rom[32768] = {0};
    rom[0x100] = 0xc3; rom[0x101] = 0x50; rom[0x102] = 1;
    rom[0x147] = 0xfc; rom[0x149] = 4;
    size_t pc = 0x150;
    emit_write(rom, &pc, 0x0000, 0x0a);
    emit_write(rom, &pc, 0x4000, 0x10);
    emit_write(rom, &pc, 0xa001, 4);
    emit_write(rom, &pc, 0xa002, 0x10);
    emit_write(rom, &pc, 0xa003, 0);
    for (unsigned i = 0; i < 48; i++) emit_write(rom, &pc, 0xa006 + i, 64 * (i % 3 + 1));
    emit_write(rom, &pc, 0x4000, 0);
    uint16_t loop = pc;
    uint8_t wait[] = {0xfa, 0xef, 0xa0, 0xb7, 0x28, 0xfa};
    memcpy(rom + pc, wait, sizeof(wait)); pc += sizeof(wait);
    emit_write(rom, &pc, 0xa0ef, 0);
    emit_write(rom, &pc, 0x4000, 0x10);
    emit_write(rom, &pc, 0xa000, 1);
    uint8_t busy[] = {0xfa, 0x00, 0xa0, 0xe6, 0x01, 0x20, 0xf9};
    memcpy(rom + pc, busy, sizeof(busy)); pc += sizeof(busy);
    emit_write(rom, &pc, 0x4000, 0);
    uint8_t result[] = {0xfa, 0x00, 0xa1, 0xea, 0xe0, 0xa0, 0xfa, 0x01, 0xa1, 0xea, 0xe1, 0xa0};
    memcpy(rom + pc, result, sizeof(result)); pc += sizeof(result);
    emit_write(rom, &pc, 0xa0ee, 0x42);
    rom[pc++] = 0xc3; rom[pc++] = loop & 255; rom[pc++] = loop >> 8;
    uint8_t boot[256] = {0xc3, 0xfc, 0};
    boot[0xfc] = 0x3e; boot[0xfd] = 1; boot[0xfe] = 0xe0; boot[0xff] = 0x50;
    SBInstance *instance = SBCreate(SB_MODEL_CGB);
    assert(instance && SBLoadBootROM(instance, boot, sizeof(boot)));
    assert(SBLoadROM(instance, rom, sizeof(rom)) && SBSkipBootROM(instance, NULL, 0));
    (void)SBRunFrame(instance);
    return instance;
}

static void sensor(SBInstance *instance, uint8_t r, uint8_t g, uint8_t b)
{
    uint8_t rgb[SENSOR_SIZE * 3];
    for (size_t i = 0; i < SENSOR_SIZE; i++) {
        rgb[i * 3] = r; rgb[i * 3 + 1] = g; rgb[i * 3 + 2] = b;
    }
    assert(SBSetCameraRGBFrame(instance, rgb, sizeof(rgb)));
    assert(!SBSetCameraRGBFrame(instance, rgb, sizeof(rgb) - 1));
    assert(!SBSetCameraRGBFrame(instance, rgb, sizeof(rgb) + 1));
}

static void shoot(SBInstance *instance, uint8_t *battery, const uint8_t request[16], bool accepted,
                  uint8_t low, uint8_t high, bool preview)
{
    size_t size = SBBatterySize(instance);
    assert(SBSaveBattery(instance, battery, size));
    memcpy(battery + 0xf0, request, 16);
    battery[0xef] = 1; battery[0xee] = 0;
    SBLoadBattery(instance, battery, size);
    if (preview) {
        SBFrameView frame;
        assert(SBRefreshFrame(instance, &frame));
    }
    (void)SBRunFrame(instance);
    assert(SBSaveBattery(instance, battery, size));
    assert(battery[0xee] == 0x42 && battery[0xef] == 0);
    assert(battery[0xe0] == low && battery[0xe1] == high);
    if (accepted) {
        assert(!memcmp(battery + 0xf0, request, 6));
        assert(!memcmp(battery + 0xf6, "HOST\x01\x00", 6));
        assert(!memcmp(battery + 0xfc, request + 12, 4));
    } else {
        assert(!memcmp(battery + 0xf0, request, 16));
    }
}

void test_camera_rgb(void)
{
    SBInstance *instance = make_camera();
    uint8_t *battery = calloc(1, SBBatterySize(instance));
    assert(battery);
    uint8_t request[16] = {'R', 'G', 'B', '?', 1, 1};
    sensor(instance, 255, 0, 128);
    shoot(instance, battery, request, true, 0, 0, false);
    // New live frames must not move a scene between the three color exposures.
    sensor(instance, 0, 255, 0);
    request[5] = 2;
    shoot(instance, battery, request, true, 255, 255, true);
    request[5] = 3;
    shoot(instance, battery, request, true, 255, 0, false);
    request[5] = 1;
    shoot(instance, battery, request, true, 255, 255, false);
    request[5] = 0;
    shoot(instance, battery, request, true, 255, 0, false);
    // Starting out of order takes a fresh image instead of a previous group's channels.
    request[5] = 2;
    shoot(instance, battery, request, true, 0, 0, false);
    sensor(instance, 255, 255, 255);
    for (unsigned invalid = 0; invalid < 5; invalid++) {
        uint8_t malformed[16] = {'R', 'G', 'B', '?', 1, 1};
        switch (invalid) {
            case 0: malformed[3] = '!'; break;
            case 1: malformed[4] = 2; break;
            case 2: malformed[5] = 4; break;
            case 3: malformed[12] = 1; break;
            case 4: memcpy(malformed + 6, "HOST\x01\x00", 6); break;
        }
        shoot(instance, battery, malformed, false, 0, 0, false);
    }
    assert(SBSetCameraRGBFrame(instance, NULL, 0));
    request[5] = 1;
    shoot(instance, battery, request, true, 255, 0, false);
    sensor(instance, 0, 255, 0);
    SBReset(instance);
    assert(SBSkipBootROM(instance, NULL, 0));
    (void)SBRunFrame(instance);
    request[5] = 2;
    shoot(instance, battery, request, true, 0, 0, false);
    free(battery);
    SBDestroy(instance);
}
