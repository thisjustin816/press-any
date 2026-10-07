// Runs one Game Boy test ROM through SameBoyBridge, the way the app runs a game, and prints
// "pass" or "fail" with a reason. Scripts/test-accuracy-roms.sh runs every suite with it.
//
// usage: sameboy_test_roms <dmg|cgb> <boot-rom> <blargg|mooneye> <seconds> <rom>
//
// blargg:  the test prints "Passed" or "Failed" over the serial port, or, in the newer tests,
//          leaves its result code at $A000 behind the signature DE B0 61 at $A001, with 0 a pass
//          and $80 still running.
// mooneye: the test leaves 3, 5, 8, 13, 21, 34 in B, C, D, E, H and L when it passes, and 0x42 in
//          all six when it fails (Mooneye Test Suite and SameSuite).

#include "SameBoyBridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t *read_file(const char *path, size_t *size)
{
    FILE *file = fopen(path, "rb");
    if (!file) return NULL;
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);
    uint8_t *bytes = length > 0 ? malloc((size_t)length) : NULL;
    if (bytes && fread(bytes, 1, (size_t)length, file) != (size_t)length) {
        free(bytes);
        bytes = NULL;
    }
    fclose(file);
    *size = bytes ? (size_t)length : 0;
    return bytes;
}

int main(int argc, char **argv)
{
    if (argc != 6) {
        fprintf(stderr, "usage: %s <dmg|cgb> <boot-rom> <blargg|mooneye> <seconds> <rom>\n", argv[0]);
        return 2;
    }
    SBModel model = strcmp(argv[1], "cgb") == 0 ? SB_MODEL_CGB : SB_MODEL_DMG;
    bool blargg = strcmp(argv[3], "blargg") == 0;
    double seconds = atof(argv[4]);

    size_t boot_size = 0, rom_size = 0;
    uint8_t *boot = read_file(argv[2], &boot_size);
    uint8_t *rom = read_file(argv[5], &rom_size);
    if (!boot || !rom) {
        printf("fail: can't read %s\n", boot ? argv[5] : argv[2]);
        return 1;
    }

    SBInstance *instance = SBCreate(model);
    if (!instance || !SBLoadBootROM(instance, boot, boot_size) || !SBLoadROM(instance, rom, rom_size)) {
        printf("fail: the bridge didn't load the ROM\n");
        return 1;
    }
    SBCaptureSerial(instance, blargg);

    char serial[8192] = {0};
    size_t serial_length = 0;
    uint64_t limit = (uint64_t)(seconds * 1e9);
    uint64_t elapsed = 0;
    const char *result = NULL;
    while (elapsed < limit && !result) {
        elapsed += SBRunFrame(instance).emulated_nanoseconds;
        if (blargg) {
            serial_length += SBDrainSerial(instance, (uint8_t *)serial + serial_length, sizeof(serial) - 1 - serial_length);
            serial[serial_length] = '\0';
            bool signed_result = SBReadMemory(instance, 0xa001) == 0xde && SBReadMemory(instance, 0xa002) == 0xb0
                && SBReadMemory(instance, 0xa003) == 0x61;
            uint8_t code = SBReadMemory(instance, 0xa000);
            if (strstr(serial, "Passed") || (signed_result && code == 0)) result = "pass";
            else if (strstr(serial, "Failed") || (signed_result && code != 0x80)) {
                result = "fail: the test reported a failure";
            }
        } else {
            SBRegisters r = SBReadRegisters(instance);
            if (r.b == 3 && r.c == 5 && r.d == 8 && r.e == 13 && r.h == 21 && r.l == 34) result = "pass";
            else if (r.b == 0x42 && r.c == 0x42 && r.d == 0x42 && r.e == 0x42 && r.h == 0x42 && r.l == 0x42) {
                result = "fail: the test reported a failure";
            }
        }
    }
    printf("%s\n", result ? result : "fail: no result before the time limit");

    SBDestroy(instance);
    free(boot);
    free(rom);
    return 0;
}
