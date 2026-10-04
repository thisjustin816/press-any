#include "ZGBMain.h"

UINT8 next_state = StateGame;

/* Called by the ZGB scroll code for every map tile; this project has no
   entity tiles, so never replace anything. */
UINT8 GetTileReplacement(UINT8* tile_ptr, UINT8* tile) {
	*tile = *tile_ptr;
	return 255u;
}
