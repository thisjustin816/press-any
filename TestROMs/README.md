# test-roms-v1

Small original Game Boy / Game Boy Color test ROMs for screenshot-testing an emulator app.
Each gameplay ROM shows its name, the SDK and its exact version, and "GB" or "GBC", plus a bouncing sprite and a
pressed-button indicator, so gameplay screenshots look alive and input is visible. Everything is built
from the source in `src/`. No commercial ROMs, boot ROMs, fetched games, toolchain installs or build
caches are included.

`manifest.json` lists every ROM and patch with filename, system, SDK, SDK version, mapper, SHA-256,
size, `hero` and `tags`. Patch entries name their source and target ROM. `SHA256SUMS` covers
everything in `roms/` and `patches/` (`sha256sum -c SHA256SUMS` from this directory).

## Layout

| Path | Contents |
| --- | --- |
| `roms/` | the built `.gb` / `.gbc` files, flat |
| `patches/` | `.ips` and `.bps` patches |
| `src/<rom-name>/` | source, `build.sh` and `LICENSE` (plus `NOTICE` and any third-party license text) for each ROM |
| `src/patch-tools/` | builds and self-checks the IPS and BPS patches |
| `src/release-tools/` | `roms.json` (tags, heroes, SDK names) and `make_manifest.py` |
| `build.sh` | rebuilds everything from clean |

## ROMs

| File | System | SDK and version | Mapper | Notes |
| --- | --- | --- | --- | --- |
| `gbdk450-dmg.gb` | GB | GBDK-2020 4.5.0 | ROM ONLY | hero |
| `gbdk406-dmg.gb` | GB | GBDK-2020 4.0.6 | ROM ONLY | older 4.0.x |
| `palette-dmg.gb` | GB | RGBDS 1.0.4 | ROM ONLY | four BG shades and OBP0/OBP1 sprite rows; A maps sprite color 1 to shade 0 |
| `rgbds-dmg.gb` | GB | RGBDS 1.0.4 | ROM ONLY | pure assembly, hero |
| `gbstudio-dmg.gb` | GB | GB Studio 4.3.2 | MBC5+RUMBLE+RAM+BATTERY | mono mode, hero |
| `hugedriver-dmg.gb` | GB | hUGEDriver a3cbd0c, RGBDS 1.0.4 | ROM ONLY | plays hUGEDriver's sample song |
| `zgb-dmg.gb` | GB | ZGB v2023.0 on GBDK-2020 4.1.1 | MBC1 | |
| `gbdk450-gbc.gbc` | GBC | GBDK-2020 4.5.0 | ROM ONLY | GBC-only, header 0x143 = 0xC0 |
| `gbdk450-dual.gbc` | GBC | GBDK-2020 4.5.0 | ROM ONLY | dual-mode (0x80), inverted gray on DMG, color on GBC, hero |
| `rgbds-gbc.gbc` | GBC | RGBDS 1.0.4 | ROM ONLY | GBC-only (`rgbfix -C`) |
| `gbstudio-gbc.gbc` | GBC | GB Studio 4.3.2 | MBC5+RUMBLE+RAM+BATTERY | color mode, hero |
| `mbc5-battery.gb` | GB | GBDK-2020 4.5.0 | MBC5+RAM+BATTERY | 8 KB cart RAM; save counter +1 per boot and per A press, hero |
| `gbdk450-rev-v1.0.gb` | GB | GBDK-2020 4.5.0 | ROM ONLY | revision pair v1.0, hero |
| `gbdk450-rev-v1.1.gb` | GB | GBDK-2020 4.5.0 | ROM ONLY | v1.1: new text, faster ball |
| `gbdk450-badsum.gb` | GB | GBDK-2020 4.5.0 | ROM ONLY | header checksum (0x14D) deliberately wrong |

`patches/gbdk450-rev-v1.0-to-v1.1.ips` and `.bps` turn v1.0 into v1.1. The bad-checksum ROM is
rejected by PyBoy ("Cartridge header checksum mismatch") and runs once the byte is corrected.

## Toolchain versions (pinned)

Versions were chosen on 2026-10-04 from the upstream tag lists (the GitHub API is not reachable from
the build environment, so "latest" means the highest release tag listed).

| Tool | Version | Source |
| --- | --- | --- |
| GBDK-2020 (latest 4.x) | 4.5.0 | release `gbdk-linux64.tar.gz`, sha256 `d7857a5f6d135ee4c249043ca26aad9f2ec8ab5d4106d97720d404114f42605c` |
| GBDK-2020 (older 4.0.x) | 4.0.6 | release `gbdk-linux64.tar.gz`, sha256 `fecdadbeb5dcab5ceebff67ff4a7630bf6f572880d4e86ac600585d8064dc7c1` |
| GBDK-2020 (for ZGB) | 4.1.1 | release `gbdk-linux64.tar.gz`, sha256 `221d0b0834709db65717f98f3eb10fc0d60039b054aa76eb93d020d0ae7bfa5a` |
| RGBDS | 1.0.4 | release `rgbds-linux-x86_64.tar.xz`, sha256 `3e19e50ea602e316be709160acaf0a708b1fa6d32d219ec541f244442895dbb7` |
| GB Studio | 4.3.2 | `gb-studio-cli` built from tag `v4.3.2` (commit `ccb891b2670134ba8237416772eea4ed09d34e1e`), Node 22.22.0, bundled GBDK 4.5.0 |
| hUGEDriver | untoxa/hUGEDriver commit `a3cbd0cea48e6784d7f625066d0300f7cb075926` | fetched by `src/hugedriver-dmg/build.sh` and hash-checked, not kept in the repository |
| ZGB | tag `v2023.0`, commit `ffca1a1bcb8407a592ec559d5dfac9bebc543836` | not vendored; `ZGB_PATH` |
| ZGB-Template | commit `37a5da36e04ed6551ce15cb94804450c3b77c7dc` | structural reference only, nothing copied |
| Python | 3.11.15 | asset scripts, patch tools, manifest |
| PyBoy | 2.7.0 | used to check the ROMs, not needed to build |

ZGB v2023.0 does not link with GBDK 4.5.0 (duplicate `.refresh_OAM`) and needs `sdcc -msm83`, which
4.0.6 lacks, so it is built with 4.1.1.

## Rebuilding

Install the toolchains above somewhere with a short path (GBDK-2020 4.5.0 aborts on long paths), then:

    GBDK_450=/opt/gbdk GBDK_406=/opt/tc/gbdk406 GBDK_411=/opt/tc/g411/gbdk \
    RGBDS_HOME=/opt/tc/rgbds ZGB_PATH=/opt/tc/zgb GBSTUDIO_CLI=gb-studio-cli ./build.sh

`build.sh` deletes `roms/`, `patches/`, `manifest.json` and `SHA256SUMS`, builds every ROM, builds and
self-checks the patches (each is applied back to v1.0 and compared with v1.1), then regenerates the
manifest and checksums. Each ROM also builds on its own with `OUT_DIR=<dir> sh src/<rom-name>/build.sh`.

To repackage: `cd ..; zip -X -r test-roms-v1.zip test-roms-v1`.

Reproducibility: two clean runs gave identical bytes for every ROM except the two GB Studio ones, whose
bytes differ between builds (not investigated). The shipped GB Studio hashes are the ones in
`manifest.json`; a rebuild changes them and the manifest with them.

The palette fixture draws background shade 0..3 at x=0,8,16,24 on y=0. Sprite rows at y=32
and y=48 use OBJ0 and OBJ1 respectively, with raw colors 1..3 at x=0,8,16. Holding A maps
sprite color 1 to shade 0, covering all four entries despite transparent raw color 0. The
SameBoy package tests check its pixels headless with the boot logo shown and skipped.

## What was checked

The gameplay ROMs were run headless in PyBoy 2.7.0 and screenshotted: text legible, the sprite moves
between frames, and holding buttons changes the indicator. The dual-mode ROM was run with `cgb=True` and
`cgb=False`. The battery ROM was power-cycled three times with `pb.stop(save=True)`: the counter reached
1, then 5 after three A presses, then 6, and the save file is the 8192-byte `.ram`. hUGEDriver output
was confirmed non-silent in PyBoy's sound buffer. The IPS and BPS patches were verified only with the
round-trip in `src/patch-tools/make_patches.py`, which is my own implementation of both formats; no
third-party patcher (Flips, beat) was available to cross-check. Nothing was run on hardware, and audio
was not listened to.

Text is small on the GBDK, RGBDS, hUGEDriver and ZGB ROMs (8x8 tile fonts at 20 columns). The GB Studio
ROMs use scaled background art and have the largest text.

## Licenses

* Original code and assets in every `src/<rom-name>/`: MIT (`LICENSE`, "Copyright (c) 2026 Press Any test
  ROM authors").
* GBDK-2020 runtime and library linked into the GBDK ROMs (and into GB Studio and ZGB ROMs): GNU GPL v2
  with a linking exception, so the ROM is not itself put under the GPL. The notice is in each GBDK-built
  directory as `THIRD_PARTY_GBDK_LICENSE.txt`; GB Studio and ZGB directories carry theirs in `NOTICE`.
* GB Studio engine and runtime in the `gbstudio-*` ROMs: MIT, Chris Maltby and contributors (see each
  `NOTICE`).
* ZGB engine in `zgb-dmg.gb`: MIT, Gonzalo de Santos Garcia (`src/zgb-dmg/LICENSE-ZGB.txt`).
* hUGEDriver and its sample song: public domain (see `src/hugedriver-dmg/NOTICE`).
* RGBDS is a build tool only; nothing from it is linked into the ROMs.
