# Original test project; the layout and these variables follow the ZGB
# makefile convention documented in the ZGB README.
# Run through ../build.sh, which supplies ZGB_PATH, GBDK_HOME and PATH.
PROJECT_NAME = zgb-dmg

all: build_gb

# Number of banks (must be a power of 2): A (Automatic), 2, 4, 8, 16, 32...
N_BANKS = 2

# Music player is unused (no music assets); keep the default driver.
MUSIC_PLAYER = HUGETRACKER

# Default hardware sprites size: SPRITES_8x16(default) or SPRITES_8x8
DEFAULT_SPRITES_SIZE = SPRITES_8x16

# Cartridge header title (makebin -yn), DMG-only (no -yc)
BINFLAGS += -yn ZGBDMGTEST

include $(ZGB_PATH)/src/MakefileCommon
