#include "SameBoyBridge.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// Each byte the test ROM receives is stored from WRAM's start, so a test can read the printer's
// replies back.
#define REPLIES 0xc000u

static void send_byte(uint8_t *rom, size_t *pc, uint8_t value)
{
    // Start an internal-clock serial transfer, wait for all eight bits and keep the reply.
    const uint8_t code[] = {
        0x3e, value, 0xe0, 0x01, 0x3e, 0x81, 0xe0, 0x02,
        0xf0, 0x02, 0xe6, 0x80, 0x20, 0xfa, 0xf0, 0x01, 0x22,
    };
    memcpy(rom + *pc, code, sizeof(code));
    *pc += sizeof(code);
}

// About 6.7 microseconds an iteration at normal speed.
static void wait_loop(uint8_t *rom, size_t *pc, uint16_t iterations)
{
    const uint8_t code[] = {0x01, iterations & 255, iterations >> 8, 0x0b, 0x78, 0xb1, 0x20, 0xfb};
    memcpy(rom + *pc, code, sizeof(code));
    *pc += sizeof(code);
}

static void wait_ms(uint8_t *rom, size_t *pc, unsigned ms)
{
    wait_loop(rom, pc, (uint16_t)(ms * 149u));
}

// A packet, with an optional wait after every byte of its payload.
static void packet_paced(uint8_t *rom, size_t *pc, uint8_t command, const uint8_t *data, size_t count,
                         unsigned payload_gap_ms)
{
    uint8_t header[] = {0x88, 0x33, command, 0, count & 255, count >> 8};
    uint16_t checksum = command + (count & 255) + (count >> 8);
    for (size_t i = 0; i < sizeof(header); i++) send_byte(rom, pc, header[i]);
    for (size_t i = 0; i < count; i++) {
        checksum += data[i];
        send_byte(rom, pc, data[i]);
        if (payload_gap_ms) wait_ms(rom, pc, payload_gap_ms);
    }
    send_byte(rom, pc, checksum & 255);
    send_byte(rom, pc, checksum >> 8);
    send_byte(rom, pc, 0);
    send_byte(rom, pc, 0);
}

static void packet(uint8_t *rom, size_t *pc, uint8_t command, const uint8_t *data, size_t count)
{
    packet_paced(rom, pc, command, data, count, 0);
}

static void start_rom(uint8_t *rom, size_t *pc)
{
    memset(rom, 0, 32768);
    rom[0x100] = 0xc3; rom[0x101] = 0x50; rom[0x102] = 1;
    *pc = 0x150;
    // ld hl, REPLIES
    rom[(*pc)++] = 0x21; rom[(*pc)++] = REPLIES & 255; rom[(*pc)++] = REPLIES >> 8;
}

static void end_rom(uint8_t *rom, size_t *pc)
{
    // Stop in a loop.
    rom[*pc] = 0x18; rom[*pc + 1] = 0xfe; *pc += 2;
    assert(*pc < 32768);
}

static SBInstance *boot(const uint8_t *rom)
{
    uint8_t boot_rom[256] = {0xc3, 0xfc, 0};
    boot_rom[0xfc] = 0x3e; boot_rom[0xfd] = 1; boot_rom[0xfe] = 0xe0; boot_rom[0xff] = 0x50;
    SBInstance *instance = SBCreate(SB_MODEL_DMG);
    assert(instance && SBLoadBootROM(instance, boot_rom, sizeof(boot_rom)));
    assert(SBLoadROM(instance, rom, 32768));
    SBSetPrinterConnected(instance, true);
    assert(SBSkipBootROM(instance, NULL, 0));
    return instance;
}

// The status byte the printer sent for a packet that ended at reply index `end` (exclusive).
static uint8_t status_at(SBInstance *instance, unsigned end)
{
    assert(SBReadMemory(instance, REPLIES + end - 2) == 0x81);
    return SBReadMemory(instance, REPLIES + end - 1);
}

static void fill_tiles(uint8_t *tiles, size_t count)
{
    for (size_t i = 0; i < count; i += 2) {
        tiles[i] = 0x55; tiles[i + 1] = 0x33;
    }
}

void test_printer(void);

// The printer's own rules, from its firmware: Print needs the empty data packet first; a
// pause of 125 ms between packets wipes what it holds; bytes more than 5.12 ms apart drop
// the packet.
static void test_printer_firmware_rules(void)
{
    uint8_t *rom = malloc(32768);
    uint8_t tiles[640];
    const uint8_t print[] = {1, 0x00, 0xe4, 0x40};
    size_t pc;
    SBPrinterOutput output;
    assert(rom);
    fill_tiles(tiles, sizeof(tiles));

    // Print without the empty data packet: a packet error, and nothing prints.
    start_rom(rom, &pc);
    packet(rom, &pc, 1, NULL, 0);
    packet(rom, &pc, 4, tiles, sizeof(tiles));
    packet(rom, &pc, 2, print, sizeof(print));
    end_rom(rom, &pc);
    SBInstance *instance = boot(rom);
    for (unsigned i = 0; i < 300; i++) (void)SBRunFrame(instance);
    assert(status_at(instance, 10) == 0x00);          // Init
    assert(status_at(instance, 10 + 650) == 0x00);    // the first data packet
    assert(status_at(instance, 10 + 650 + 14) & 0x10); // Print: packet error
    assert(!SBPopPrinterOutput(instance, &output));
    SBDestroy(instance);

    // Two bands with 200 ms between them: the printer resets in the pause and prints the
    // second band alone; its data packet is answered 00, the first after a reset.
    start_rom(rom, &pc);
    packet(rom, &pc, 1, NULL, 0);
    packet(rom, &pc, 4, tiles, sizeof(tiles));
    wait_ms(rom, &pc, 200);
    packet(rom, &pc, 4, tiles, sizeof(tiles));
    packet(rom, &pc, 4, NULL, 0);
    packet(rom, &pc, 2, print, sizeof(print));
    end_rom(rom, &pc);
    instance = boot(rom);
    for (unsigned i = 0; i < 300; i++) (void)SBRunFrame(instance);
    assert(status_at(instance, 10 + 650 + 650) == 0x00);
    assert(SBPopPrinterOutput(instance, &output) && output.height == 16);
    SBDestroy(instance);

    // The same two bands back to back: the second is answered 08, and both print.
    start_rom(rom, &pc);
    packet(rom, &pc, 1, NULL, 0);
    packet(rom, &pc, 4, tiles, sizeof(tiles));
    packet(rom, &pc, 4, tiles, sizeof(tiles));
    packet(rom, &pc, 4, NULL, 0);
    packet(rom, &pc, 2, print, sizeof(print));
    end_rom(rom, &pc);
    instance = boot(rom);
    // Busy shows partway, and two bands take about two seconds.
    bool printing_at_one_second = false;
    for (unsigned i = 0; i < 400; i++) {
        (void)SBRunFrame(instance);
        if (i == 140) printing_at_one_second = SBGetPrinterActivity(instance) == SB_PRINTER_PRINTING;
    }
    assert(printing_at_one_second);
    assert(status_at(instance, 10 + 650 + 650) == 0x08);
    assert(SBPopPrinterOutput(instance, &output) && output.height == 32);
    SBDestroy(instance);

    // Payload bytes 8 ms apart: the printer drops the packet and answers 0xFF.
    uint8_t few[8];
    fill_tiles(few, sizeof(few));
    start_rom(rom, &pc);
    packet(rom, &pc, 1, NULL, 0);
    packet_paced(rom, &pc, 4, few, sizeof(few), 8);
    end_rom(rom, &pc);
    instance = boot(rom);
    for (unsigned i = 0; i < 60; i++) (void)SBRunFrame(instance);
    assert(status_at(instance, 10) == 0x00);
    assert(SBReadMemory(instance, REPLIES + 10 + 18 - 2) == 0xff);
    SBDestroy(instance);
    free(rom);
}

void test_printer(void)
{
    uint8_t rom[32768] = {0};
    rom[0x100] = 0xc3; rom[0x101] = 0x50; rom[0x102] = 1;
    size_t pc = 0x150;
    // The replies go to WRAM from its start; ld hl, REPLIES.
    rom[pc++] = 0x21; rom[pc++] = REPLIES & 255; rom[pc++] = REPLIES >> 8;
    packet(rom, &pc, 1, NULL, 0);
    uint8_t tiles[640];
    fill_tiles(tiles, sizeof(tiles));
    packet(rom, &pc, 4, tiles, sizeof(tiles));
    packet(rom, &pc, 4, NULL, 0);
    const uint8_t print[] = {1, 0x23, 0xe4, 0x40};
    packet(rom, &pc, 2, print, sizeof(print));
    // Wait three emulated seconds before submitting another job.
    for (unsigned i = 0; i < 8; i++) wait_loop(rom, &pc, 0);
    rom[pc++] = 0xc3; rom[pc++] = 0x50; rom[pc++] = 1;
    assert(pc < sizeof(rom));
    SBInstance *instance = boot(rom);
    SBPrinterOutput output;
    bool received = false, printing = false;
    assert(SBGetPrinterActivity(instance) == SB_PRINTER_IDLE);
    assert(!SBPopPrinterOutput(instance, &output));
    // Transfer takes about 0.7 seconds, and a band with five margin units about 1.6 seconds.
    for (unsigned i = 0; i < 200; i++) {
        (void)SBRunFrame(instance);
        received |= SBGetPrinterActivity(instance) == SB_PRINTER_RECEIVING;
        printing |= SBGetPrinterActivity(instance) == SB_PRINTER_PRINTING;
    }
    assert(received && printing);
    assert(SBGetPrinterActivity(instance) == SB_PRINTER_IDLE);
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
    assert(SBGetPrinterActivity(instance) == SB_PRINTER_IDLE);
    SBReset(instance);
    for (unsigned i = 0; i < 200; i++) (void)SBRunFrame(instance);
    assert(!SBPopPrinterOutput(instance, &output));
    SBDestroy(instance);
    test_printer_firmware_rules();
}
