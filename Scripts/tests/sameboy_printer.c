#include "SameBoyBridge.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static void send_byte(uint8_t *rom, size_t *pc, uint8_t value)
{
    // Start an internal-clock serial transfer and wait for all eight bits.
    const uint8_t code[] = {
        0x3e, value, 0xe0, 0x01, 0x3e, 0x81, 0xe0, 0x02,
        0xf0, 0x02, 0xe6, 0x80, 0x20, 0xfa,
    };
    memcpy(rom + *pc, code, sizeof(code));
    *pc += sizeof(code);
}

static void packet(uint8_t *rom, size_t *pc, uint8_t command, const uint8_t *data, size_t count)
{
    uint8_t header[] = {0x88, 0x33, command, 0, count & 255, count >> 8};
    uint16_t checksum = command + (count & 255) + (count >> 8);
    for (size_t i = 0; i < sizeof(header); i++) send_byte(rom, pc, header[i]);
    for (size_t i = 0; i < count; i++) {
        checksum += data[i];
        send_byte(rom, pc, data[i]);
    }
    send_byte(rom, pc, checksum & 255);
    send_byte(rom, pc, checksum >> 8);
    send_byte(rom, pc, 0);
    send_byte(rom, pc, 0);
}

void test_printer(void)
{
    uint8_t rom[32768] = {0};
    rom[0x100] = 0xc3; rom[0x101] = 0x50; rom[0x102] = 1;
    size_t pc = 0x150;
    packet(rom, &pc, 1, NULL, 0);
    uint8_t tiles[640];
    for (size_t i = 0; i < sizeof(tiles); i += 2) {
        tiles[i] = 0x55; tiles[i + 1] = 0x33;
    }
    packet(rom, &pc, 4, tiles, sizeof(tiles));
    const uint8_t print[] = {1, 0x23, 0xe4, 0x40};
    packet(rom, &pc, 2, print, sizeof(print));
    // Wait three emulated seconds before submitting another job.
    for (unsigned i = 0; i < 8; i++) {
        const uint8_t delay[] = {0x01, 0x00, 0x00, 0x0b, 0x78, 0xb1, 0x20, 0xfb};
        memcpy(rom + pc, delay, sizeof(delay)); pc += sizeof(delay);
    }
    rom[pc++] = 0xc3; rom[pc++] = 0x50; rom[pc++] = 1;
    assert(pc < sizeof(rom));
    uint8_t boot[256] = {0xc3, 0xfc, 0};
    boot[0xfc] = 0x3e; boot[0xfd] = 1; boot[0xfe] = 0xe0; boot[0xff] = 0x50;
    SBInstance *instance = SBCreate(SB_MODEL_DMG);
    assert(instance && SBLoadBootROM(instance, boot, sizeof(boot)));
    assert(SBLoadROM(instance, rom, sizeof(rom)));
    SBSetPrinterConnected(instance, true);
    assert(SBSkipBootROM(instance, NULL, 0));
    SBPrinterOutput output;
    assert(!SBPopPrinterOutput(instance, &output));
    // Transfer takes about 0.7 seconds, and sixteen print rows take two seconds.
    for (unsigned i = 0; i < 200; i++) (void)SBRunFrame(instance);
    SBFrameView preview;
    assert(SBRefreshFrame(instance, &preview));
    assert(SBPopPrinterOutput(instance, &output));
    assert(output.height == 16 && output.top_margin == 2 && output.bottom_margin == 3);
    assert(output.exposure == 64);
    for (size_t i = 0; i < 160u * output.height; i++) {
        assert(output.luminance[i] == 255 - (i % 4) * 85);
    }
    const char *sample_path = getenv("PRINTER_SAMPLE_PATH");
    if (sample_path) {
        FILE *sample = fopen(sample_path, "wb");
        assert(sample);
        assert(fwrite(output.luminance, 1, 160u * output.height, sample) == 160u * output.height);
        assert(fclose(sample) == 0);
    }
    assert(!SBPopPrinterOutput(instance, &output));
    assert(!SBConsumePrinterOverflow(instance));
    SBReset(instance);
    for (unsigned i = 0; i < 200; i++) (void)SBRunFrame(instance);
    assert(SBPopPrinterOutput(instance, &output));
    for (unsigned i = 0; i < 4800; i++) (void)SBRunFrame(instance);
    assert(SBConsumePrinterOverflow(instance));
    assert(!SBConsumePrinterOverflow(instance));
    unsigned retained = 0;
    while (SBPopPrinterOutput(instance, &output)) retained++;
    assert(retained == 16);
    SBSetPrinterConnected(instance, false);
    SBReset(instance);
    for (unsigned i = 0; i < 200; i++) (void)SBRunFrame(instance);
    assert(!SBPopPrinterOutput(instance, &output));
    SBDestroy(instance);
}
