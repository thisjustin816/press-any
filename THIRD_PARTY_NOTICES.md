# Third-Party Notices

Press Any uses these third-party projects, artwork and data. Dependencies are pinned without
copying source snapshots into this repository. Adapted code, artwork and data carry their source notices.

## SameBoy

- Project: SameBoy
- Author: Lior Halphon
- Upstream: https://github.com/LIJI32/SameBoy
- Location: git submodule at `Packages/EmulatorKit/Dependencies/SameBoy`
- Pinned commit: `19a7b14cfb10bb20b0f931b3d77359c11f866e17` (`v1.0.4-53-g19a7b14c`, master on
  2026-10-28)
- Why this commit and not the `v1.0.4` tag: the commits after the tag include upstream
  `ecd0b5f`, which stops a WX register write from also landing in `hram`, where it overwrote a
  byte of the Game Boy Camera's dither matrix. They also stop MBC3 and TPP1 clocks from counting
  time while a game has halted them, apply six-digit Game Genie codes and cheats in cartridge RAM
  banks, expose the camera's shoot flags, fix Super Game Boy `MLT_REQ`, refuse truncated states
  with an error, and model the infrared sensor more closely. Version 1.0.4 itself fixes Super
  Game Boy command reading, MMM01 detection and reads past the core's memory when loading a
  damaged state. States saved by the previous pin (`213a12c`) load unchanged. Move to a release
  tag once one contains these fixes.
- Usage: only `Core/` is compiled, behind Press Any's `SameBoyBridge`. The boot ROMs are built
  from the submodule's `BootROMs/` sources. Nothing from SameBoy's iOS frontend (`iOS/`), whose
  license needs the author's written permission for App Store distribution, is compiled,
  bundled or adapted. The eighteen boot palette choices (twelve button combinations and six
  game palettes) copy RGB555 values and combination mappings from `BootROMs/cgb_boot.asm`
  into `SameBoyBridge/SameBoyBootPalettes.h`, which carries the Expat notice. Their background/OBJ0/OBJ1 use is checked against Pan Docs:
  https://gbdev.io/pandocs/Power_Up_Sequence.html#compatibility-palettes.
  Press Any's controller layouts and artwork are its own.
- License: Expat (MIT-style); see the submodule's `LICENSE`.

## GRDB.swift

- Project: GRDB.swift
- Upstream: https://github.com/groue/GRDB.swift
- Pinned version: 7.11.1
- Usage: SQLite persistence through Swift Package Manager.
- License: MIT; see the pinned upstream package for the authoritative license text.

## Libretro thumbnails

- Source: https://github.com/libretro-thumbnails/libretro-thumbnails
- Service: https://thumbnails.libretro.com
- Usage: optional online box-art lookup using recognized GB/GBC release names. No game
  artwork or thumbnail repository is bundled in the app or committed as a fixture.
- Credits: the Libretro thumbnail community's scanners, collectors and contributors;
  upstream also credits MobyGames and Fandom as sources.
- Rights: original game and promotional artwork belongs to the respective developers and
  publishers. The repository does not establish a blanket artwork redistribution license.
  A fetched image keeps its source URL and this rights notice in the player's local library.
  This credit grants no additional rights to the app or its users.

## Corporatus wordmark

- Authors: Alex Rosario and Roc Mitchell.
- Source: https://asr.me/font/corp.html
- Typeface version: Corporatus Regular 1.002, copyright (c) 2017 Alex Rosario.
- Usage: fixed wordmark artwork in the library, welcome screen, controller menu button and
  placeholder cartridge plaques.
- Location: outlined PDFs in the `Wordmark`, `WordmarkRecess` and `WordmarkPlaque` image sets
  in `App/Assets.xcassets`. The font software is not included in the repository or app.
- License: purchased Desktop license for static artwork. The supplied copyright notice and
  published Desktop terms are bundled in `App/Acknowledgements/Corporatus-LICENSE.txt`.
- Export: `Scripts/render-wordmark.py` takes a separately licensed font outside the checkout,
  reads the display name from `project.yml` and colors from the named assets, and exports
  fixed outlines. The controller recess tones are defined in the export script.

## gbtoolsid

- Project: gbtoolsid (Game Boy Toolchain ID)
- Upstream: https://github.com/bbbbbr/gbtoolsid
- Ported revision: `v1.5.5-14-g5ff49ad` (`5ff49ad1282178eaebf47314d0c775c2b13d98b8`), an
  untagged commit on main. No release includes its GB Studio 4.3+ detection yet, so the port
  follows main rather than the v1.5.5 tag.
- Usage: `Packages/EmulatorKit/Sources/ToolchainDetection/GB` is a Swift port of its detection
  logic. `GBToolsIDData.swift` is generated from its `src/entry_names_*.h` signature tables by
  `Scripts/generate-gbtoolsid-data.py`; the `check_*` functions are translated by hand. The
  app links the port and runs it in process; no gbtoolsid source or binary ships, and the app
  never runs the gbtoolsid tool.
- Verification: `Scripts/test-toolchain-detection-differential.sh` builds gbtoolsid at the
  ported revision and requires the port to produce identical results on its test ROMs and on
  synthetic ROMs. The test ROMs are fetched at run time and never committed here.
- License: public domain, under the Unlicense (https://unlicense.org).

## No-Intro data

- Project: No-Intro's DAT-o-MATIC (https://datomatic.no-intro.org)
- Data: the DB exports for "Nintendo - Game Boy" and "Nintendo - Game Boy Color". The versions in
  use are in the header of `Packages/EmulatorKit/Sources/GameIdentity/Resources/KnownDumps.json`.
- Usage: `Scripts/generate-known-dumps.py` reduces them to each game's canonical name, title,
  region, languages, development status, version, aftermarket and unlicensed flags, family root,
  and each file's SHA-1, size and bad-dump flag. The app bundles that file and matches imported
  ROMs against it. No ROM, image or other No-Intro content ships.
- License: DAT-o-MATIC's Data Usage License (updated 2026-09-11) permits the data to be "freely
  used, copied, reproduced, modified, adapted, combined, published, distributed, and otherwise
  reused by anyone for any lawful purpose", commercially or not, with no attribution required.
  The app credits No-Intro in Acknowledgements anyway.
- Refreshing: `docs/release.md`, "Refreshing the No-Intro data".

## Test ROMs

- Location: `TestROMs/`. Not part of the app or its tests' build.
- Original code and assets: MIT. The ROMs link the GBDK-2020 runtime (GPL v2 with a linking
  exception), and the GB Studio and ZGB ROMs link those engines (MIT). Each directory under
  `TestROMs/src/` carries the notices; `TestROMs/README.md` lists the versions.
- hUGEDriver (public domain) is fetched at a pinned commit by its ROM's build, not kept here.

## Accuracy test ROMs

- Projects: [Blargg's test ROMs](https://github.com/retrio/gb-test-roms) and the
  [Mooneye Test Suite](https://github.com/Gekkio/mooneye-test-suite) (MIT), assembled with
  [WLA DX](https://github.com/vhelin/wla-dx), at the commits
  [game-boy-test-roms](https://github.com/c-sp/game-boy-test-roms) v7.0 uses.
- Usage: `Scripts/test-accuracy-roms.sh` fetches and builds them at run time to check the core's
  results. None of them is committed here or ships in the app.

## Device display shaders

- SameBoy Monochrome LCD and LCD by Lior Halphon: ported from `Shaders/MonoLCD.fsh`,
  `Shaders/LCD.fsh` and the gamma wrapper in `Shaders/MasterShader.metal` at the existing
  SameBoy pin. These are outside its restricted `iOS/` directory and use its Expat license.
  The bundled `App/Acknowledgements/SameBoy-LICENSE.txt` applies. The constants retain the
  upstream defaults. Source: https://github.com/LIJI32/SameBoy/tree/19a7b14cfb10bb20b0f931b3d77359c11f866e17/Shaders.
- Authentic GBC v2.2 by fishku (fishcu), copyright 2024-2025: CC0. The Metal port uses the
  single-pass preset, shared notched-subpixel geometry and analytical coverage helpers with
  default brightness 0.6, smoothing 0.3 and display-subpixel rendering disabled. Its original
  license declaration and CC0 text are bundled in `App/Acknowledgements/AuthenticGBC-LICENSE.txt`.
- CRT-Lottes by Timothy Lottes: public domain. The Metal port retains the upstream default
  reconstruction kernels, beam, bloom, shadow mask and sRGB transfer. The app adds edge
  feathering/falloff and a current/previous-field adapter for its denser GBP television raster.
  This is a curated RGB CRT approximation, not a composite decoder or an emulation of a named TV.
- GBA and SP101 color shaders by Pokefan531 and hunterk, optimized by crashGG: public domain.
  The ports use the upstream sRGB matrices, luminance and zero screen-darkening defaults.
  AGB uses the GBA profile; backlit AGS-101 uses SP101. Core color
  correction is disabled for these configurations so the profile is applied only once.
- Libretro sources above are pinned to `53deb2efcb79f4fc3e94e9602d5974b4b64e8f94` in `slang-shaders`:
  https://github.com/libretro/slang-shaders/tree/53deb2efcb79f4fc3e94e9602d5974b4b64e8f94.
  Paths: `handheld/shaders/authentic_gbc/`, `misc/shaders/coverage/coverage.inc`,
  `crt/shaders/crt-lottes.slang`, `handheld/shaders/color/gba-color.slang` and
  `handheld/shaders/color/sp101-color.slang`. Public-domain declarations and source URLs are
  bundled in `App/Acknowledgements/DisplayShaders-PublicDomain.txt`.
- The app credits each author in Settings > Acknowledgements. `App/Gameplay/DisplayShaders.h`
  contains the Metal adaptations. Neither GPL LCD1x nor GPL CRT shader code is included.
- Legacy `lcd1x` and `lcd3x` setting identifiers remain decodable. Their menu treatments are
  SameBoy Monochrome LCD and Authentic GBC respectively; retired LCD3x is omitted from the menu.

## Game Boy Printer firmware research

- Project: Game-Boy-Printer-disassembly, by Raphaël Boichot
- Upstream: https://github.com/Raphael-Boichot/Game-Boy-Printer-disassembly
- Revision consulted: `990c3b6`
- Usage: `Packages/EmulatorKit/Sources/SameBoyBridge/SBGameBoyPrinter.c` models the Game Boy
  Printer from the protocol its firmware implements, as `Printer_protocol.md` documents it from
  a disassembly of the printer's ROM, and from timings measured with its firmware emulator
  (`emulator/gbprinter_emu.py`). The model is Press Any's own code: no source, ROM or binary
  from the project is copied or shipped. Its replies were checked byte for byte against that
  emulator running the printer's firmware; the check ran outside this repository. One rule
  departs from that reading: a data packet after a finished Print needs an Init first, because a
  physical printer refused one without it.
- License: the project states none. Nothing is copied; it is credited in Acknowledgements.

## In the app

Settings > Acknowledgements lists the code, artwork and data used in the app. SameBoy's,
GRDB.swift's and Corporatus's notices are bundled in `App/Acknowledgements/`; gbtoolsid, which is in
the public domain, No-Intro and the Game Boy Printer firmware research get a credit. Device shader notices are
bundled with the app and their authors are listed in Acknowledgements.

## Updating a dependency

Updating a pin is an explicit change: update it, copy its license into `App/Acknowledgements/`
if it changed, run the platform-independent tests and the device checks in
`docs/mvp-verification.md`, and record the reason here. A SameBoy update is a
core migration candidate: existing Builds keep their pinned core until they are migrated
deliberately. An update that keeps the state format and the behavior saves depend on, checked by
loading states from the previous pin, can instead name the previous version in the core's
`replacedDescriptors`: Builds pinned to it then run on the new one and their states load.
`1.0.5-prerelease.53+19a7b14` replaces 1.0.3 this way, and 1.0.4, the label this commit first
shipped under.

A pin on a release tag takes that version as its core version, such as `1.0.5`. A pin between
releases takes the next patch version as a prerelease numbered by the commits since the last tag,
with the commit after `+`: `1.0.5-prerelease.53+19a7b14` is 53 commits after `v1.0.4`. It sorts
before the release it leads to and after earlier pins, and never claims to be a release.


## Printer wood background

- Asset: Wood Table
- Author: Dimitrios Savva
- Source: https://polyhaven.com/a/wood_table
- Download: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/wood_table/wood_table_diff_1k.jpg
- Location: `App/Resources/PrinterWood.jpg` (original 1K photograph)
- SHA-256: `f81642ae141958feac6c5acac03e2aeb6cfe049dff301d0627e3c17f2dc5c7a5`
- Usage: optional Wood background behind exported printer slips.
- License: CC0 1.0 Universal, https://polyhaven.com/license and
  https://creativecommons.org/publicdomain/zero/1.0/; the legal text is bundled in
  `App/Acknowledgements/PrinterWood-CC0.txt`.
