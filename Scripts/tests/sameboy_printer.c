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

static SBInstance *boot_model(const uint8_t *rom, SBModel model)
{
    uint8_t boot_rom[256] = {0xc3, 0xfc, 0};
    boot_rom[0xfc] = 0x3e; boot_rom[0xfd] = 1; boot_rom[0xfe] = 0xe0; boot_rom[0xff] = 0x50;
    SBInstance *instance = SBCreate(model);
    assert(instance && SBLoadBootROM(instance, boot_rom, sizeof(boot_rom)));
    assert(SBLoadROM(instance, rom, 32768));
    SBSetPrinterConnected(instance, true);
    assert(SBSkipBootROM(instance, NULL, 0));
    return instance;
}

static SBInstance *boot(const uint8_t *rom)
{
    return boot_model(rom, SB_MODEL_DMG);
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
void test_printer_model(void);

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

    // A Super Game Boy runs its Game Boy about 2.4% fast, and the printer keeps its own time:
    // nine copies of a band print for about 8.3 seconds, some 509 of the Super Game Boy's
    // frames, where a printer timed by the core's clock would finish after about 497.
    const uint8_t nine_copies[] = {9, 0x00, 0xe4, 0x40};
    start_rom(rom, &pc);
    packet(rom, &pc, 1, NULL, 0);
    packet(rom, &pc, 4, tiles, sizeof(tiles));
    packet(rom, &pc, 4, NULL, 0);
    packet(rom, &pc, 2, nine_copies, sizeof(nine_copies));
    end_rom(rom, &pc);
    instance = boot_model(rom, SB_MODEL_SGB);
    unsigned printing_frames = 0;
    for (unsigned i = 0; i < 700; i++) {
        (void)SBRunFrame(instance);
        printing_frames += SBGetPrinterActivity(instance) == SB_PRINTER_PRINTING;
    }
    assert(printing_frames > 503 && printing_frames < 515);
    unsigned copies = 0;
    while (SBPopPrinterOutput(instance, &output)) {
        assert(output.follows_copy == (copies > 0));
        copies++;
    }
    assert(copies == 9);
    SBDestroy(instance);
    free(rom);
}

// A game's printing: it sends a job, then polls the printer's status every 50 ms until the band
// has printed, and starts the job again on an error, up to three attempts. It counts in WRAM.
#define GAME_DONE 0xc800u     // jobs the printer reported finished
#define GAME_ERRORS 0xc801u   // error statuses seen
#define GAME_ATTEMPTS 0xc802u // jobs started
#define GAME_POLLS 0xc803u    // status polls in the current job; wraps to 0 when polling runs away
#define GAME_STALLED 0xc804u  // set when polling ran away

static void emit(uint8_t *rom, size_t *pc, const uint8_t *code, size_t size)
{
    memcpy(rom + *pc, code, size);
    *pc += size;
}

static void jump_to(uint8_t *rom, size_t at, size_t target)
{
    rom[at] = target & 255;
    rom[at + 1] = target >> 8;
}

static void make_polling_game(uint8_t *rom)
{
    size_t pc;
    start_rom(rom, &pc);
    const uint8_t clear[] = {0xaf, 0xea, 0x00, 0xc8, 0xea, 0x01, 0xc8, 0xea, 0x02, 0xc8, 0xea, 0x04, 0xc8};
    emit(rom, &pc, clear, sizeof(clear));
    size_t job = pc;
    // ld hl, REPLIES ; ld a, [ATTEMPTS] ; inc a ; ld [ATTEMPTS], a ; xor a ; ld [POLLS], a
    const uint8_t start_job[] = {0x21, REPLIES & 255, REPLIES >> 8, 0xfa, 0x02, 0xc8, 0x3c, 0xea, 0x02, 0xc8,
                                 0xaf, 0xea, 0x03, 0xc8};
    emit(rom, &pc, start_job, sizeof(start_job));
    packet(rom, &pc, 1, NULL, 0);
    uint8_t tiles[640];
    fill_tiles(tiles, sizeof(tiles));
    packet(rom, &pc, 4, tiles, sizeof(tiles));
    packet(rom, &pc, 4, NULL, 0);
    const uint8_t print[] = {1, 0x23, 0xe4, 0x40};
    packet(rom, &pc, 2, print, sizeof(print));
    size_t poll = pc;
    wait_ms(rom, &pc, 50);
    // A status poll's replies overwrite one place, so a long wait can't run past WRAM.
    const uint8_t rewind[] = {0x21, 0x00, 0xc4}; // ld hl, $C400
    emit(rom, &pc, rewind, sizeof(rewind));
    packet(rom, &pc, 0x0f, NULL, 0);
    // ld a, [POLLS] ; inc a ; ld [POLLS], a ; jp z, stalled
    const uint8_t count[] = {0xfa, 0x03, 0xc8, 0x3c, 0xea, 0x03, 0xc8, 0xca, 0, 0};
    emit(rom, &pc, count, sizeof(count));
    size_t to_stalled = pc - 2;
    // The status is the last byte received: dec hl ; ld a, [hl] ; ld b, a
    // and $F1 ; jp nz, error ; ld a, b ; and $0A ; jp nz, poll (busy or unprocessed data)
    const uint8_t check[] = {0x2b, 0x7e, 0x47, 0xe6, 0xf1, 0xc2, 0, 0, 0x78, 0xe6, 0x0a, 0xc2, 0, 0};
    emit(rom, &pc, check, sizeof(check));
    size_t to_error = pc - 8, to_poll = pc - 2;
    jump_to(rom, to_poll, poll);
    // ld a, [DONE] ; inc a ; ld [DONE], a ; jp end
    const uint8_t done[] = {0xfa, 0x00, 0xc8, 0x3c, 0xea, 0x00, 0xc8, 0xc3, 0, 0};
    emit(rom, &pc, done, sizeof(done));
    size_t done_to_end = pc - 2;
    size_t error = pc;
    jump_to(rom, to_error, error);
    // ld a, [ERRORS] ; inc a ; ld [ERRORS], a ; ld a, [ATTEMPTS] ; cp 3 ; jp c, job ; jp end
    const uint8_t retry[] = {0xfa, 0x01, 0xc8, 0x3c, 0xea, 0x01, 0xc8, 0xfa, 0x02, 0xc8, 0xfe, 0x03,
                             0xda, 0, 0, 0xc3, 0, 0};
    emit(rom, &pc, retry, sizeof(retry));
    jump_to(rom, pc - 5, job);
    size_t retry_to_end = pc - 2;
    size_t stalled = pc;
    jump_to(rom, to_stalled, stalled);
    // ld a, 1 ; ld [STALLED], a
    const uint8_t mark[] = {0x3e, 0x01, 0xea, 0x04, 0xc8};
    emit(rom, &pc, mark, sizeof(mark));
    size_t end = pc;
    jump_to(rom, done_to_end, end);
    jump_to(rom, retry_to_end, end);
    end_rom(rom, &pc);
}

typedef struct {
    unsigned done, errors, attempts, prints, rows;
    bool stalled;
} printing_outcome;

static printing_outcome finish_game(SBInstance *instance, unsigned frames, unsigned prints_before, unsigned rows_before)
{
    printing_outcome outcome = {.prints = prints_before, .rows = rows_before};
    SBPrinterOutput output;
    for (unsigned i = 0; i < frames; i++) {
        (void)SBRunFrame(instance);
        while (SBPopPrinterOutput(instance, &output)) { outcome.prints++; outcome.rows += output.height; }
    }
    outcome.done = SBReadMemory(instance, GAME_DONE);
    outcome.errors = SBReadMemory(instance, GAME_ERRORS);
    outcome.attempts = SBReadMemory(instance, GAME_ATTEMPTS);
    outcome.stalled = SBReadMemory(instance, GAME_STALLED) != 0;
    return outcome;
}

static void print_outcome(const char *what, printing_outcome o)
{
    fprintf(stderr, "%s: done %u, errors %u, attempts %u, stalled %d, prints %u (%u rows)\n",
            what, o.done, o.errors, o.attempts, o.stalled, o.prints, o.rows);
}

// Saves a state when the printer first reports `activity`, plays `frames_after` more frames,
// loads the state and plays on.
static printing_outcome restore_during(const uint8_t *rom, SBPrinterActivity activity, unsigned frames_after)
{
    SBInstance *instance = boot(rom);
    SBPrinterOutput output;
    unsigned prints = 0, rows = 0;
    for (unsigned i = 0; i < 600 && SBGetPrinterActivity(instance) != activity; i++) {
        (void)SBRunFrame(instance);
        while (SBPopPrinterOutput(instance, &output)) { prints++; rows += output.height; }
    }
    assert(SBGetPrinterActivity(instance) == activity);
    size_t size = SBStateSize(instance);
    uint8_t *state = malloc(size);
    assert(state && SBSaveState(instance, state, size));
    for (unsigned i = 0; i < frames_after; i++) {
        (void)SBRunFrame(instance);
        while (SBPopPrinterOutput(instance, &output)) { prints++; rows += output.height; }
    }
    assert(SBLoadState(instance, state, size));
    free(state);
    printing_outcome outcome = finish_game(instance, 1500, prints, rows);
    SBDestroy(instance);
    return outcome;
}

static void test_printer_state_restore(void)
{
    uint8_t rom[32768];
    make_polling_game(rom);
    SBInstance *instance = boot(rom);
    printing_outcome plain = finish_game(instance, 1500, 0, 0);
    SBDestroy(instance);
    print_outcome("uninterrupted", plain);
    assert(plain.done == 1 && plain.errors == 0 && plain.attempts == 1 && !plain.stalled);
    assert(plain.prints == 1 && plain.rows == 16);

    // A state loaded while the job was being sent: the packet the load cut into fails, and the
    // game's retry prints, once. The two ends count bits from the same place again after the next
    // quiet stretch.
    const unsigned transfer_frames[] = {2, 30};
    for (size_t i = 0; i < 2; i++) {
        printing_outcome o = restore_during(rom, SB_PRINTER_RECEIVING, transfer_frames[i]);
        print_outcome("loaded mid-transfer", o);
        assert(o.done == 1 && !o.stalled && o.errors <= 1 && o.attempts == o.errors + 1);
        assert(o.prints == 1 && o.rows == 16);
    }
    // A state loaded while the band printed, before or after it came out: the printer finishes
    // the band once, and the game sees it done.
    const unsigned print_frames[] = {2, 150};
    for (size_t i = 0; i < 2; i++) {
        printing_outcome o = restore_during(rom, SB_PRINTER_PRINTING, print_frames[i]);
        print_outcome("loaded mid-print", o);
        assert(o.done == 1 && o.errors == 0 && o.attempts == 1 && !o.stalled);
        assert(o.prints == 1 && o.rows == 16);
    }
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
    assert(output.exposure == 64 && !output.follows_copy);
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
    test_printer_model();
    test_printer_state_restore();
}
