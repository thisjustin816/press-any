/* Per-ROM text and options for main.c. */
#if REV == 0
#define ROM_TITLE "REV TEST V1.0"
#else
#define ROM_TITLE "REV TEST V1.1"
#endif
#define SDK_LINE "GBDK-2020"
#define VER_LINE "VERSION 4.5.0"
#define MODE_KIND 0 /* 0 = DMG only, 1 = GBC only, 2 = dual mode */
#define HEADER_LINE "HEADER: GB ONLY"
#if REV == 0
#define EXTRA_LINE "V1.0 FIRST RELEASE"
#define BALL_SPEED_REV 1
#else
#define EXTRA_LINE "V1.1 FASTER BALL"
#define BALL_SPEED_REV 2
#endif
#define WITH_SAVE 0
#define BALL_SPEED BALL_SPEED_REV
