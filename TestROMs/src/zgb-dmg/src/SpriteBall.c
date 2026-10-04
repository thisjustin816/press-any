#include "Banks/SetAutoBank.h"

#include "ZGBMain.h"
#include "SpriteManager.h"

/* Bounces inside the framed field: screen x 8..136, y 70..82 (sprite is
   16x16, frame inner area is y 66..101). custom_data[0..1] = signed speed. */
#define MIN_X 8
#define MAX_X 136
#define MIN_Y 70
#define MAX_Y 82

void START() {
	THIS->custom_data[0] = 1;            /* dx */
	THIS->custom_data[1] = 1;            /* dy */
}

void UPDATE() {
	INT8 dx = (INT8)THIS->custom_data[0];
	INT8 dy = (INT8)THIS->custom_data[1];
	INT16 nx = (INT16)THIS->x + dx * 2;
	INT16 ny = (INT16)THIS->y + dy;

	if(nx <= MIN_X) { nx = MIN_X; dx = 1; }
	if(nx >= MAX_X) { nx = MAX_X; dx = -1; }
	if(ny <= MIN_Y) { ny = MIN_Y; dy = 1; }
	if(ny >= MAX_Y) { ny = MAX_Y; dy = -1; }

	THIS->custom_data[0] = (UINT8)dx;
	THIS->custom_data[1] = (UINT8)dy;
	THIS->x = (UINT16)nx;
	THIS->y = (UINT16)ny;
}

void DESTROY() {
}
