#ifndef SB_GAME_BOY_PRINTER_H
#define SB_GAME_BOY_PRINTER_H

#include <stdbool.h>
#include <stdint.h>

// A Game Boy Printer that follows the printer's own firmware: its packet rules, status bits,
// timeouts and print timing. Time is in the core's 8 MHz ticks. The model sees the link one bit
// at a time, as SameBoy's serial callbacks deliver it, and reports finished prints through
// `on_print`.

#define SBP_TICKS_PER_SECOND 8388608ull
#define SBP_SLOT_BYTES 640u
#define SBP_SLOTS 9u
#define SBP_MEMORY (SBP_SLOT_BYTES * SBP_SLOTS)

typedef struct SBGameBoyPrinter SBGameBoyPrinter;

// One printed copy: pixel values 0-3 after the print's palette, 160 pixels a row.
typedef void (*SBPPrintCallback)(void *context, const uint8_t *pixels, uint8_t height,
                                 uint8_t top_margin, uint8_t bottom_margin, uint8_t exposure);

struct SBGameBoyPrinter {
    SBPPrintCallback on_print;
    void *context;
    uint64_t now;

    // Link layer.
    uint8_t in_byte, in_bits, out_byte, out_bit;
    bool any_byte;
    uint64_t last_byte;
    bool quiet_reset_done;
    bool sync_lost;

    // Packet receiver.
    uint8_t phase;
    uint8_t command, compression;
    uint16_t length, remaining, checksum, received_checksum;
    uint8_t args[4];
    uint8_t reply[2];
    bool packet_error;
    bool checksum_error_next; // Shown in the next reply.
    bool data_packet;

    // Image memory.
    uint8_t memory[SBP_MEMORY];
    uint16_t image_bytes, saved_bytes;
    uint16_t rle_run;
    bool rle_repeat;

    // Status and job flags.
    uint8_t status;
    bool end_mark, after_print, break_block, hide_full;

    // The print in progress: busy from busy_from to busy_until, its copies, and the bands of a
    // further copy that Break cut short.
    bool printing;
    uint64_t print_start, busy_from, busy_until;
    uint8_t copies, partial_bands, top_margin, bottom_margin, palette, exposure;
    uint16_t print_bytes;
};

void sbp_reset(SBGameBoyPrinter *printer, SBPPrintCallback on_print, void *context);
// Each bit the Game Boy shifts out, at time now; after eight, the byte is taken.
void sbp_bit_from_game_boy(SBGameBoyPrinter *printer, uint64_t now, bool bit);
// The bit the printer shifts back for the same clock.
bool sbp_bit_to_game_boy(SBGameBoyPrinter *printer);
// Moves time on: idle reset, the end of a print.
void sbp_advance(SBGameBoyPrinter *printer, uint64_t now);
bool sbp_is_printing(const SBGameBoyPrinter *printer);
bool sbp_is_receiving(const SBGameBoyPrinter *printer);

#endif
