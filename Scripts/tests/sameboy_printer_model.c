#include "SBGameBoyPrinter.h"
#include <assert.h>
#include <string.h>

// Drives the printer model directly, a byte a millisecond as a game sends them, with time in
// milliseconds since the test began.
static SBGameBoyPrinter printer;
static unsigned prints;
static uint8_t last_height, last_first_pixel, last_top, last_bottom, last_exposure;
static uint64_t now_ms;

static void on_print(void *context, const uint8_t *pixels, uint8_t height, uint8_t top,
                     uint8_t bottom, uint8_t exposure)
{
    (void)context;
    prints++;
    last_height = height;
    last_first_pixel = pixels[0];
    last_top = top;
    last_bottom = bottom;
    last_exposure = exposure;
}

static uint64_t ticks(uint64_t ms)
{
    return ms * SBP_TICKS_PER_SECOND / 1000u;
}

static void wait_ms(uint64_t ms)
{
    now_ms += ms;
    sbp_advance(&printer, ticks(now_ms));
}

// One byte at the current time, a bit at a time as SameBoy's callbacks deliver it.
static uint8_t exchange(uint8_t out)
{
    uint8_t in = 0;
    sbp_advance(&printer, ticks(now_ms));
    for (int bit = 0; bit < 8; bit++) {
        sbp_bit_from_game_boy(&printer, ticks(now_ms), out & 0x80);
        in = (uint8_t)(in << 1) | (sbp_bit_to_game_boy(&printer) ? 1 : 0);
        out <<= 1;
    }
    now_ms++;
    return in;
}

// Sends a packet and returns its status byte.
static uint8_t packet(uint8_t command, uint8_t compression, const uint8_t *data, uint16_t length)
{
    uint8_t header[] = {0x88, 0x33, command, compression, length & 255, length >> 8};
    uint16_t checksum = command + compression + (length & 255) + (length >> 8);
    for (size_t i = 0; i < sizeof(header); i++) exchange(header[i]);
    for (uint16_t i = 0; i < length; i++) {
        checksum += data[i];
        exchange(data[i]);
    }
    exchange(checksum & 255);
    exchange(checksum >> 8);
    assert(exchange(0) == 0x81);
    return exchange(0);
}

static void start(void)
{
    sbp_reset(&printer, on_print, NULL);
    prints = 0;
    last_height = 0;
    now_ms = 10;
    assert(packet(1, 0, NULL, 0) == 0x00);
}

static const uint8_t tiles[640] = {0x55, 0x33, 0x55, 0x33};
static const uint8_t print_one[] = {1, 0x00, 0xe4, 0x40};

// Sends `bands` data packets, the empty one and Print, and returns the Print's time.
static uint64_t print_bands(unsigned bands, const uint8_t *args)
{
    for (unsigned i = 0; i < bands; i++) packet(4, 0, tiles, sizeof(tiles));
    packet(4, 0, NULL, 0);
    packet(2, 0, args, 4);
    return now_ms;
}

// Polls a frame apart until `until` ms after `from`; returns when busy last showed.
static uint64_t poll_until(uint64_t from, uint64_t until)
{
    uint64_t busy_seen = 0;
    while (now_ms < from + until) {
        if (packet(15, 0, NULL, 0) & 0x02) busy_seen = now_ms - from;
        wait_ms(16);
    }
    return busy_seen;
}

// A literal run that ends at a band's last byte ends there, and the next byte is a control
// byte again.
static void test_run_ends_with_its_band(void)
{
    uint8_t compressed[5 * 129 + 2];
    size_t at = 0;
    for (unsigned run = 0; run < 5; run++) {
        compressed[at++] = 0x7f;
        for (unsigned i = 0; i < 128; i++) compressed[at++] = 0x11;
    }
    compressed[at++] = 0x81; // 0xaa three times
    compressed[at++] = 0xaa;
    start();
    packet(4, 1, compressed, (uint16_t)at);
    assert(printer.memory[639] == 0x11);
    assert(printer.memory[640] == 0xaa && printer.memory[641] == 0xaa && printer.memory[642] == 0xaa);
    assert(printer.memory[643] == 0x00);
}

// Once a print ends, the image it leaves in memory is not reported as one being received, even
// while the game keeps polling.
static void test_idle_after_print(void)
{
    start();
    uint64_t printed = print_bands(1, print_one);
    poll_until(printed, 1500);
    assert(prints == 1 && !sbp_is_printing(&printer));
    assert(!sbp_is_receiving(&printer));
}

// A finished Print's data needs an Init before the next image, as on a physical printer
// (header_done in SBGameBoyPrinter.c).
static void test_data_after_a_print_waits_for_an_init(void)
{
    uint8_t black[640];
    memset(black, 0xff, sizeof(black));
    start();
    uint64_t printed = print_bands(1, print_one);
    poll_until(printed, 1500);
    assert(prints == 1 && last_first_pixel == 0 && !sbp_is_printing(&printer));

    assert(packet(4, 0, black, sizeof(black)) == 0x14);
    assert(packet(4, 0, black, sizeof(black)) == 0x14);
    assert(printer.image_bytes == 640 && printer.memory[0] == 0x55);

    packet(1, 0, NULL, 0);
    assert(!(packet(4, 0, black, sizeof(black)) & 0x10));
    assert(!(packet(4, 0, NULL, 0) & 0x10));
    assert(!(packet(2, 0, print_one, sizeof(print_one)) & 0x10));
    poll_until(now_ms, 1500);
    assert(prints == 2 && last_height == 16 && last_first_pixel == 3);
}

// A job in parts, as games send one: an Init before each later part, whose reply still shows the
// last part's image full (04), and no feed margin where the parts meet.
static void test_parts_open_with_an_init(void)
{
    const uint8_t first[] = {1, 0x10, 0xe4, 0x40}, last[] = {1, 0x03, 0xe4, 0x40};
    start();
    uint64_t printed = print_bands(1, first);
    poll_until(printed, 1500);
    assert(prints == 1 && last_top == 1 && last_bottom == 0);

    assert(packet(1, 0, NULL, 0) == 0x04);
    printed = print_bands(1, last);
    poll_until(printed, 1500);
    assert(prints == 2 && last_height == 16 && last_top == 0 && last_bottom == 3);
}

// After a print, 125 ms without a byte resets the printer as an Init does: an Init then answers
// 00, and data needs no Init at all. The second half follows the firmware's idle reset; no
// physical printer has been checked for it.
static void test_idle_reset_after_a_print(void)
{
    uint8_t black[640];
    memset(black, 0xff, sizeof(black));
    start();
    uint64_t printed = print_bands(1, print_one);
    poll_until(printed, 1500);
    wait_ms(200);
    assert(packet(1, 0, NULL, 0) == 0x00);

    start();
    printed = print_bands(1, print_one);
    poll_until(printed, 1500);
    wait_ms(200);
    assert(!(packet(4, 0, black, sizeof(black)) & 0x10));
    packet(4, 0, NULL, 0);
    packet(2, 0, print_one, sizeof(print_one));
    poll_until(now_ms, 1500);
    assert(prints == 2 && last_first_pixel == 3);
}

// An Init sent while the last job still prints is refused and marks the data unprocessed, so the
// data that follows the print still needs an Init of its own.
static void test_init_while_printing_leaves_data_blocked(void)
{
    start();
    uint64_t printed = print_bands(2, print_one);
    poll_until(printed, 300);
    assert(packet(1, 0, NULL, 0) == 0x0e);
    poll_until(printed, 2500);
    assert(!sbp_is_printing(&printer));
    assert(packet(4, 0, tiles, sizeof(tiles)) == 0x14);
    packet(1, 0, NULL, 0);
    assert(packet(4, 0, tiles, sizeof(tiles)) == 0x00);
}

// Palette 0 prints as E4, 1B inverts the shades, and an exposure above 7F prints as 40.
static void test_palette_and_exposure(void)
{
    const uint8_t no_palette[] = {1, 0x00, 0x00, 0x80}, inverted[] = {1, 0x00, 0x1b, 0x7f};
    uint8_t black[640];
    memset(black, 0xff, sizeof(black));

    start();
    packet(4, 0, black, sizeof(black));
    packet(4, 0, NULL, 0);
    packet(2, 0, no_palette, sizeof(no_palette));
    poll_until(now_ms, 1500);
    assert(prints == 1 && last_first_pixel == 3 && last_exposure == 0x40);

    start();
    packet(4, 0, black, sizeof(black));
    packet(4, 0, NULL, 0);
    packet(2, 0, inverted, sizeof(inverted));
    poll_until(now_ms, 1500);
    assert(prints == 1 && last_first_pixel == 0 && last_exposure == 0x7f);
}

// Times from the printer's firmware run in its emulator: a Break while the paper feeds between
// bands stops it at the next feed step, and the band already printed comes out.
static void test_break_between_bands(void)
{
    start();
    uint64_t printed = print_bands(2, print_one);
    poll_until(printed, 880);
    packet(8, 0, NULL, 0);
    uint64_t busy = poll_until(printed, 2500);
    // The firmware stops this one about 995 ms after the Print.
    assert(busy > 960 && busy < 1000);
    assert(prints == 1 && last_height == 16);
}

// Each copy after the first adds its own band and a short feed; the top margin feeds once.
static void test_copies_take_their_time(void)
{
    const uint8_t two_copies[] = {2, 0x10, 0xe4, 0x40};
    start();
    uint64_t printed = print_bands(1, two_copies);
    uint64_t busy = poll_until(printed, 2500);
    // The firmware ends this job about 1,933 ms after the Print.
    assert(busy > 1880 && busy < 1950);
    assert(prints == 2 && last_height == 16);
}

static SBPEvent events[64];
static unsigned event_count;

static void on_event(void *context, const SBPEvent *event)
{
    (void)context;
    if (event_count < 64) events[event_count++] = *event;
}

// Data sent while a print runs is dropped without an error bit, so the log marks it; status polls
// are logged only when their answer changes.
static void test_events_name_what_the_printer_dropped(void)
{
    start();
    sbp_set_event_callback(&printer, on_event);
    event_count = 0;
    print_bands(1, print_one);
    assert(event_count == 3);
    assert(events[0].command == 4 && events[0].length == 640 && !events[0].ignored);
    assert(events[2].command == 2 && events[2].checksum_ok);
    wait_ms(200);
    packet(15, 0, NULL, 0);
    packet(15, 0, NULL, 0);
    assert(event_count == 4 && events[3].command == 15 && (events[3].status & 0x02));
    uint8_t status = packet(4, 0, tiles, sizeof(tiles));
    assert(event_count == 5 && events[4].ignored && events[4].status == status);
    assert(!(status & 0x10));

    // A packet cut off mid-way is reported when the next byte arrives too late.
    start();
    sbp_set_event_callback(&printer, on_event);
    event_count = 0;
    exchange(0x88);
    exchange(0x33);
    exchange(4);
    wait_ms(20);
    exchange(0x88);
    assert(event_count == 1 && events[0].kind == SBP_EVENT_TIMEOUT && events[0].command == 4);
}

void test_printer_model(void)
{
    test_run_ends_with_its_band();
    test_idle_after_print();
    test_data_after_a_print_waits_for_an_init();
    test_parts_open_with_an_init();
    test_idle_reset_after_a_print();
    test_init_while_printing_leaves_data_blocked();
    test_palette_and_exposure();
    test_break_between_bands();
    test_copies_take_their_time();
    test_events_name_what_the_printer_dropped();
}
