#include "Banks/SetAutoBank.h"

#include "ZGBMain.h"
#include "Keys.h"
#include "Print.h"
#include "Scroll.h"
#include "SpriteManager.h"

IMPORT_MAP(bkg);
IMPORT_MAP(font);

/* Fixed-position fields so each held button lights up in its own slot.
   Unheld slots are blanked. */
static void ShowKey(UINT8 x, UINT8 y, UINT8 held, const char* name, UINT8 len) {
	UINT8 i;
	if(held) {
		PRINT(x, y, name);
	} else {
		print_x = x; print_y = y;
		for(i = 0; i != len; ++i) Printf(" ");
	}
}

void START() {
	UINT16 v = __GBDK_VERSION;  /* e.g. 450 -> 4.5.0 */

	InitScroll(BANK(bkg), &bkg, 0, 0);

	/* ZGB Print(): load the font tiles after the map tiles and print on BKG */
	print_target = PRINT_BKG;
	font_offset = ScrollSetTiles(last_tile_loaded, font.tiles_bank, font.tiles);

	PRINT(4, 0, "ZGB DMG TEST");
	PRINT(4, 2, "ZGB v2023.0");
	PRINT(4, 4, "GBDK %u.%u.%u", v / 100u, (v / 10u) % 10u, v % 10u);
	PRINT(4, 6, "GB");
	PRINT(0, 13, "HELD:");

	SpriteManagerAdd(SpriteBall, 20, 76);
}

void UPDATE() {
	UINT8 any = KEY_PRESSED(J_UP | J_DOWN | J_LEFT | J_RIGHT | J_A | J_B | J_START | J_SELECT);
	ShowKey(6, 13, !any, "NONE", 4);
	ShowKey(0, 15, KEY_PRESSED(J_UP),    "UP",    2);
	ShowKey(3, 15, KEY_PRESSED(J_DOWN),  "DOWN",  4);
	ShowKey(8, 15, KEY_PRESSED(J_LEFT),  "LEFT",  4);
	ShowKey(13, 15, KEY_PRESSED(J_RIGHT), "RIGHT", 5);
	ShowKey(0, 17, KEY_PRESSED(J_A),      "A",      1);
	ShowKey(2, 17, KEY_PRESSED(J_B),      "B",      1);
	ShowKey(4, 17, KEY_PRESSED(J_START),  "START",  5);
	ShowKey(10, 17, KEY_PRESSED(J_SELECT), "SELECT", 6);
}
