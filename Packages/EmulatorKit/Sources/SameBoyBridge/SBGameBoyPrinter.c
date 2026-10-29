#include "SBGameBoyPrinter.h"

#include <string.h>

// The rules and timings come from the printer's firmware, as Raphaël Boichot's
// Game-Boy-Printer-disassembly documents it (Printer_protocol.md) and runs it in its firmware
// emulator (https://github.com/Raphael-Boichot/Game-Boy-Printer-disassembly). The 4 ms per pixel
// column was checked on a real printer there; the paper feed of a margin unit was not, so the
// print times that include it are the emulator's.
#define SBP_MS(ms) ((uint64_t)(ms) * SBP_TICKS_PER_SECOND / 1000u)
#define SBP_BYTE_TIMEOUT (SBP_TICKS_PER_SECOND * 512u / 100000u) // 5.12 ms between bytes.
#define SBP_IDLE_RESET SBP_MS(125)    // Without a byte while not printing, the printer re-inits.
#define SBP_BUSY_DELAY SBP_MS(30)     // Busy shows, and the paper starts, this long after Print.
#define SBP_MARGIN_UNIT SBP_MS(160)   // One unit of margin; the paper also feeds in steps this long.
#define SBP_FEED_ONLY SBP_MS(13)      // A print with no copies only feeds, after this long.
#define SBP_BAND_PRINT SBP_MS(638)    // Printing one band, up to its end in band_end_ms.
#define SBP_COPY_FEED SBP_MS(108)     // The feed before each copy after the first.
#define SBP_STEP_PHASE SBP_MS(7)      // Feed steps start this long after a band ends.
// Break stops the paper at a feed step at least SBP_BREAK_LEAD away, or as the next band
// starts if that is at least SBP_BREAK_BEFORE_BAND away.
#define SBP_BREAK_LEAD SBP_MS(45)
#define SBP_BREAK_BEFORE_BAND SBP_MS(80)
// How long into the feed before a copy's first band a Break still stops it.
#define SBP_BREAK_LEAD_IN SBP_MS(75)

enum {
    SBP_CHECKSUM = 0x01, SBP_BUSY = 0x02, SBP_FULL = 0x04, SBP_UNPROCESSED = 0x08,
    SBP_PACKET_ERROR = 0x10, SBP_JAM = 0x20, SBP_OTHER = 0x40, SBP_LOW_BATTERY = 0x80,
};

enum {
    SBP_MAGIC1, SBP_MAGIC2, SBP_COMMAND, SBP_COMPRESSION, SBP_LENGTH_LOW, SBP_LENGTH_HIGH,
    SBP_PAYLOAD, SBP_CHECKSUM_LOW, SBP_CHECKSUM_HIGH, SBP_ALIVE, SBP_STATUS_SLOT,
};

enum { SBP_INIT = 1, SBP_PRINT = 2, SBP_DATA = 4, SBP_BREAK = 8, SBP_NUL = 15 };

static bool busy_now(const SBGameBoyPrinter *p)
{
    return p->printing && p->now >= p->busy_from;
}

static void init(SBGameBoyPrinter *p)
{
    p->status &= (uint8_t)~(SBP_FULL | SBP_UNPROCESSED);
    p->image_bytes = 0;
    p->end_mark = p->after_print = p->break_block = p->packet_error = false;
    p->rle_run = 0;
}

void sbp_reset(SBGameBoyPrinter *p, SBPPrintCallback on_print, void *context)
{
    memset(p, 0, sizeof(*p));
    p->on_print = on_print;
    p->context = context;
}

void sbp_set_event_callback(SBGameBoyPrinter *p, SBPEventCallback on_event)
{
    p->on_event = on_event;
}

static void report(SBGameBoyPrinter *p, uint8_t kind, uint8_t command)
{
    if (!p->on_event) return;
    SBPEvent event = {
        .time = p->now, .kind = kind, .command = command, .compression = p->compression,
        .status = p->reply[1], .length = p->length, .checksum_ok = true,
    };
    p->on_event(p->context, &event);
}

// From the start of a copy, after any top margin, to the end of each 16-row band. The bands
// after the first take 1,117, 1,129 and 1,272 ms in turn, as the paper cam comes round.
static const uint16_t band_end_ms[SBP_SLOTS] = {828, 1945, 3074, 4346, 5475, 6592, 7864, 8993, 10110};

static uint64_t band_end(uint8_t bands)
{
    return SBP_MS(band_end_ms[bands - 1u]);
}

static uint8_t bands_of(uint16_t bytes)
{
    return (uint8_t)((bytes + SBP_SLOT_BYTES - 1u) / SBP_SLOT_BYTES);
}

// From the Print command to the end of the job. The top margin feeds once, the bottom margin
// after every copy.
static uint64_t print_ticks(const SBGameBoyPrinter *p)
{
    uint8_t bands = bands_of(p->print_bytes);
    uint64_t top = p->top_margin * SBP_MARGIN_UNIT, bottom = p->bottom_margin * SBP_MARGIN_UNIT;
    if (!p->copies || !bands) return SBP_FEED_ONLY + top + bottom;
    uint64_t copy = band_end(bands) + bottom;
    return top + copy + (p->copies - 1u) * (SBP_COPY_FEED + copy);
}

// The full copies, then the bands of a copy Break cut short.
static void deliver(SBGameBoyPrinter *p)
{
    if (!p->on_print || !p->print_bytes || (!p->copies && !p->partial_bands)) return;
    uint8_t bands = bands_of(p->print_bytes);
    uint8_t pixels[160u * 16u * SBP_SLOTS];
    // Bands are 2 rows of 20 tiles; a short last band prints the zeroes past the data.
    for (unsigned band = 0; band < bands; band++) {
        for (unsigned tile = 0; tile < 40u; tile++) {
            const uint8_t *data = p->memory + band * SBP_SLOT_BYTES + tile * 16u;
            unsigned top = band * 16u + (tile / 20u) * 8u, left = (tile % 20u) * 8u;
            for (unsigned y = 0; y < 8u; y++) {
                uint16_t at = (uint16_t)(band * SBP_SLOT_BYTES + tile * 16u + y * 2u);
                uint8_t low = at < p->print_bytes ? data[y * 2u] : 0;
                uint8_t high = at + 1u < p->print_bytes ? data[y * 2u + 1u] : 0;
                for (unsigned x = 0; x < 8u; x++) {
                    uint8_t value = (uint8_t)(((low >> (7u - x)) & 1u) | (((high >> (7u - x)) & 1u) << 1));
                    pixels[(top + y) * 160u + left + x] = (uint8_t)((p->palette >> (value * 2u)) & 3u);
                }
            }
        }
    }
    for (uint8_t copy = 0; copy < p->copies; copy++) {
        p->on_print(p->context, pixels, (uint8_t)(bands * 16u), p->top_margin, p->bottom_margin,
                    p->exposure);
    }
    if (p->partial_bands) {
        p->on_print(p->context, pixels, (uint8_t)(p->partial_bands * 16u), p->top_margin,
                    p->bottom_margin, p->exposure);
    }
}

void sbp_advance(SBGameBoyPrinter *p, uint64_t now)
{
    if (now < p->now) return;
    p->now = now;
    if (p->printing && now >= p->busy_until) {
        p->printing = false;
        p->status &= (uint8_t)~SBP_UNPROCESSED;
        deliver(p);
    }
    if (!p->any_byte || p->printing || p->quiet_reset_done) return;
    uint64_t since = p->last_byte > p->busy_until ? p->last_byte : p->busy_until;
    if (now - since >= SBP_IDLE_RESET) {
        // The activity timer only counts while the printer is idle; when it runs out, the
        // printer clears its memory and status as an Init does.
        if (p->image_bytes && !p->after_print) report(p, SBP_EVENT_IDLE_RESET, 0);
        init(p);
        p->quiet_reset_done = true;
    }
}

bool sbp_is_printing(const SBGameBoyPrinter *p)
{
    return p->printing;
}

// Image memory still holds a printed job until the next data packet, so it counts only before
// a Print.
bool sbp_is_receiving(const SBGameBoyPrinter *p)
{
    return (p->image_bytes && !p->after_print) || (p->data_packet && p->phase == SBP_PAYLOAD);
}

static void store(SBGameBoyPrinter *p, uint8_t byte)
{
    if (p->image_bytes >= SBP_MEMORY) return; // Memory full: the rest is dropped silently.
    p->memory[p->image_bytes++] = byte;
    // A run never crosses into the next slot.
    if (p->image_bytes % SBP_SLOT_BYTES == 0) p->rle_run = 0;
}

static void take_payload(SBGameBoyPrinter *p, uint8_t byte)
{
    if (!p->compression) {
        store(p, byte);
        return;
    }
    // RLE: a control byte below 0x80 copies the next c+1 bytes, from 0x80 the next byte
    // repeats (c & 0x7f) + 2 times.
    if (!p->rle_run) {
        p->rle_repeat = byte & 0x80;
        p->rle_run = p->rle_repeat ? (uint16_t)((byte & 0x7f) + 2u) : (uint16_t)(byte + 1u);
        return;
    }
    // store() ends the run at a slot's end, so count the byte first.
    if (!p->rle_repeat) {
        p->rle_run--;
        store(p, byte);
        return;
    }
    while (p->rle_run && p->image_bytes < SBP_MEMORY) {
        p->rle_run--;
        store(p, byte);
    }
    p->rle_run = 0;
}

// The header is complete: decide what this packet may do, as the firmware's receiver does.
static void header_done(SBGameBoyPrinter *p)
{
    // Only a data packet's payload is kept; any other payload fills args, and the rest of it
    // only counts toward the checksum.
    p->data_packet = false;
    p->ignored_data = false;
    if (p->command != SBP_NUL) p->packet_error = false;
    switch (p->command) {
        case SBP_DATA:
            if (p->printing) { // Data while printing is ignored.
                p->ignored_data = p->length > 0;
                break;
            }
            if (p->length >= 0x400u) {
                if (!p->compression) p->packet_error = true;
                break;
            }
            if (!p->length) {
                if (p->compression || (p->status & SBP_FULL)) p->packet_error = true;
                else {
                    p->status |= SBP_FULL;
                    p->end_mark = true;
                    p->hide_full = true;
                }
                break;
            }
            if (p->break_block) {
                p->packet_error = true;
                break;
            }
            if (p->after_print) {
                p->after_print = false;
                p->status &= (uint8_t)~SBP_FULL;
                p->end_mark = false;
                p->image_bytes = 0;
            }
            if ((p->status & SBP_FULL) || p->compression > 1u) {
                p->packet_error = true;
                break;
            }
            p->data_packet = true;
            p->saved_bytes = p->image_bytes;
            p->rle_run = 0;
            break;
        case SBP_PRINT:
            if (!p->end_mark || p->length < 4u) p->packet_error = true;
            break;
        case SBP_NUL:
            // A status poll ends the empty data packet's mask and, while idle, the unprocessed
            // flag as it arrives, so its own reply already shows both.
            p->hide_full = false;
            if (!p->printing) p->status &= (uint8_t)~SBP_UNPROCESSED;
            if (p->length >= 0x400u) p->packet_error = true;
            break;
        case SBP_BREAK:
            if (p->length >= 0x400u) p->packet_error = true;
            break;
        default:
            break;
    }
}

static uint8_t reply_status(SBGameBoyPrinter *p)
{
    uint8_t status = (uint8_t)(p->status & ~(SBP_BUSY | SBP_PACKET_ERROR));
    if (busy_now(p)) status |= SBP_BUSY;
    if (p->packet_error) status |= SBP_PACKET_ERROR;
    if (p->command == SBP_INIT && p->printing) status |= SBP_UNPROCESSED;
    if (p->hide_full) status &= (uint8_t)~SBP_FULL;
    if (p->data_packet) status &= (uint8_t)~SBP_BUSY;
    return status;
}

// The first feed step at least SBP_BREAK_LEAD after `t`, for paper fed from `from`.
static uint64_t next_step(uint64_t from, uint64_t phase, uint64_t t)
{
    uint64_t step = from + phase;
    while (step < t + SBP_BREAK_LEAD) step += SBP_MARGIN_UNIT;
    return step;
}

// Where a Break at `t` after the Print stops the job, and the full copies and bands of a
// further copy printed by then. A band being printed is finished. Paper fed for a margin or
// between bands stops at a feed step. In the feed before a copy's first band, an early Break
// stops the paper as the band would start and a later one lets the band print; the feed between
// copies ignores Break. False when the job ends first.
static bool break_point(const SBGameBoyPrinter *p, uint64_t t, uint64_t *end, uint8_t *copies,
                        uint8_t *bands)
{
    uint8_t count = bands_of(p->print_bytes);
    uint64_t base = p->top_margin * SBP_MARGIN_UNIT;
    *copies = *bands = 0;
    if (!p->copies || !count) {
        *end = next_step(0, SBP_BUSY_DELAY, t);
        return *end < p->busy_until - p->print_start;
    }
    for (uint8_t copy = 0; copy < p->copies; copy++) {
        uint64_t first = base + band_end(1) - SBP_BAND_PRINT;
        *copies = copy;
        if (t < base) {
            if (copy) return false;
            // The top margin.
            uint64_t step = next_step(0, SBP_BUSY_DELAY, t);
            *end = step < first ? step : first;
            return true;
        }
        if (t < first && t < base + SBP_BREAK_LEAD_IN) {
            *end = first;
            return true;
        }
        for (uint8_t band = 1; band <= count; band++) {
            uint64_t printed = base + band_end(band), printing = printed - SBP_BAND_PRINT;
            if (t >= printed) continue;
            *bands = band;
            *end = printed;
            if (band > 1u && t < printing) {
                uint64_t step = next_step(base + band_end(band - 1u), SBP_STEP_PHASE, t);
                if (step < printing) *end = step;
                else if (printing - t >= SBP_BREAK_BEFORE_BAND) *end = printing;
                if (*end != printed) *bands = band - 1u;
            }
            return true;
        }
        // The bottom margin. Its last step ends with it.
        uint64_t last = base + band_end(count), copy_end = last + p->bottom_margin * SBP_MARGIN_UNIT;
        uint64_t step = next_step(last, SBP_STEP_PHASE, t);
        if (t < copy_end && step <= copy_end + SBP_STEP_PHASE) {
            *copies = copy + 1u;
            *bands = 0;
            *end = step < copy_end ? step : copy_end;
            return true;
        }
        base = copy_end + SBP_COPY_FEED;
    }
    return false;
}

static void stop(SBGameBoyPrinter *p)
{
    uint64_t end;
    uint8_t copies, bands;
    if (!break_point(p, p->now - p->print_start, &end, &copies, &bands)) return;
    p->busy_until = p->print_start + end;
    if (p->copies) {
        p->copies = copies;
        p->partial_bands = bands;
    }
}

// The checksum's second byte is in: the reply is prepared before the compare, so a bad
// checksum shows in the next reply. Then the command runs, as the firmware's main loop does.
static void packet_done(SBGameBoyPrinter *p)
{
    bool previous_bad = p->status & SBP_CHECKSUM;
    p->reply[0] = 0x81;
    p->reply[1] = reply_status(p);
    bool good = p->checksum == p->received_checksum;
    if (good) p->status &= (uint8_t)~SBP_CHECKSUM;
    else {
        p->status |= SBP_CHECKSUM;
        if (p->command != SBP_PRINT && p->command != SBP_BREAK) {
            p->status &= (uint8_t)~SBP_FULL;
            p->end_mark = false;
        }
    }
    if (p->on_event && (p->command != SBP_NUL || !p->polled || p->polled_status != p->reply[1])) {
        if (p->command == SBP_NUL) {
            p->polled = true;
            p->polled_status = p->reply[1];
        }
        SBPEvent event = {
            .time = p->now, .kind = SBP_EVENT_PACKET, .command = p->command,
            .compression = p->compression, .status = p->reply[1], .length = p->length,
            .checksum_ok = good,
            .ignored = p->ignored_data,
        };
        p->on_event(p->context, &event);
    }
    if (p->data_packet && (!good || p->packet_error)) p->image_bytes = p->saved_bytes;
    if (p->data_packet && p->compression && good && !p->packet_error) {
        // A compressed packet fills the rest of its slot with zeroes.
        while (p->image_bytes % SBP_SLOT_BYTES && p->image_bytes < SBP_MEMORY) store(p, 0);
    }
    if (!good || previous_bad || p->packet_error) return;
    switch (p->command) {
        case SBP_INIT:
            // While printing, Init is refused and marks the data unprocessed.
            if (p->printing) p->status |= SBP_UNPROCESSED;
            else init(p);
            break;
        case SBP_DATA:
            // The firmware marks compressed data a few milliseconds later, once its main loop
            // has decoded the packet; here it is marked as soon as the packet ends.
            if (p->data_packet && p->length) p->status |= SBP_UNPROCESSED;
            break;
        case SBP_PRINT:
            if (p->printing) break;
            p->after_print = true;
            p->copies = p->args[0];
            p->top_margin = p->args[1] >> 4;
            p->bottom_margin = p->args[1] & 0x0f;
            p->palette = p->args[2] ? p->args[2] : 0xe4; // 0 means no remapping.
            p->exposure = p->args[3] > 0x7f ? 0x40 : p->args[3];
            p->print_bytes = p->image_bytes;
            p->partial_bands = 0;
            p->status &= (uint8_t)~SBP_UNPROCESSED;
            p->printing = true;
            p->print_start = p->now;
            p->busy_from = p->now + SBP_BUSY_DELAY;
            p->busy_until = p->now + print_ticks(p);
            break;
        case SBP_BREAK:
            if (p->printing) stop(p);
            p->break_block = true;
            break;
        default:
            break;
    }
}

static void byte_in(SBGameBoyPrinter *p, uint8_t byte)
{
    if (p->any_byte && p->now - p->last_byte > SBP_BYTE_TIMEOUT) {
        // The inter-byte timer ran out: the packet in progress is dropped and rolled back.
        if (p->phase > SBP_MAGIC2 && p->phase < SBP_ALIVE) {
            report(p, SBP_EVENT_TIMEOUT, p->phase > SBP_COMMAND ? p->command : 0);
        }
        if (p->phase != SBP_MAGIC1 && p->data_packet) p->image_bytes = p->saved_bytes;
        p->phase = SBP_MAGIC1;
        p->data_packet = false;
        p->sync_lost = false;
    }
    p->any_byte = true;
    p->last_byte = p->now;
    p->quiet_reset_done = false;
    p->out_byte = 0;
    if (p->sync_lost) {
        p->out_byte = 0xff;
        return;
    }
    switch (p->phase) {
        case SBP_MAGIC1:
            if (byte != 0x88) {
                // A bad first byte: answer 0xFF until the line goes quiet, and re-init if idle.
                if (!p->printing) init(p);
                report(p, SBP_EVENT_SYNC_LOST, byte);
                p->sync_lost = true;
                p->out_byte = 0xff;
                return;
            }
            p->checksum = 0;
            p->phase = SBP_MAGIC2;
            return;
        case SBP_MAGIC2:
            if (byte != 0x33) {
                p->out_byte = 0xff;
                p->phase = SBP_MAGIC1;
                return;
            }
            p->phase = SBP_COMMAND;
            return;
        case SBP_COMMAND:
            p->command = byte;
            p->checksum = byte;
            p->phase = SBP_COMPRESSION;
            return;
        case SBP_COMPRESSION:
            p->compression = byte;
            p->checksum += byte;
            p->phase = SBP_LENGTH_LOW;
            return;
        case SBP_LENGTH_LOW:
            p->length = byte;
            p->checksum += byte;
            p->phase = SBP_LENGTH_HIGH;
            return;
        case SBP_LENGTH_HIGH:
            p->length |= (uint16_t)(byte << 8);
            p->checksum += byte;
            p->remaining = p->length;
            p->phase = p->length ? SBP_PAYLOAD : SBP_CHECKSUM_LOW;
            header_done(p);
            return;
        case SBP_PAYLOAD: {
            uint16_t index = (uint16_t)(p->length - p->remaining);
            p->checksum += byte;
            if (p->data_packet) take_payload(p, byte);
            else if (index < 4u) p->args[index] = byte;
            if (!--p->remaining) p->phase = SBP_CHECKSUM_LOW;
            return;
        }
        case SBP_CHECKSUM_LOW:
            p->received_checksum = byte;
            p->phase = SBP_CHECKSUM_HIGH;
            return;
        case SBP_CHECKSUM_HIGH:
            p->received_checksum |= (uint16_t)(byte << 8);
            packet_done(p);
            p->out_byte = p->reply[0];
            p->phase = SBP_ALIVE;
            return;
        case SBP_ALIVE:
            p->out_byte = p->reply[1];
            p->phase = SBP_STATUS_SLOT;
            return;
        default:
            p->data_packet = false;
            p->phase = SBP_MAGIC1;
            return;
    }
}

void sbp_bit_from_game_boy(SBGameBoyPrinter *p, uint64_t now, bool bit)
{
    sbp_advance(p, now);
    p->in_byte = (uint8_t)(p->in_byte << 1) | (bit ? 1u : 0u);
    if (++p->in_bits < 8u) return;
    p->in_bits = 0;
    byte_in(p, p->in_byte);
    p->in_byte = 0;
}

// The printer answers one bit behind the clock, as SameBoy's serial callbacks expect: the byte
// chosen when a byte completes goes out during the next one.
bool sbp_bit_to_game_boy(SBGameBoyPrinter *p)
{
    bool bit = p->out_bit;
    p->out_bit = p->out_byte & 0x80;
    p->out_byte = (uint8_t)(p->out_byte << 1);
    return bit;
}
