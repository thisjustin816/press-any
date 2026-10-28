# Third-Party Notices

Press Any uses these third-party projects, artwork and data. Dependencies are pinned without
copying source snapshots into this repository. Adapted code, artwork and data carry their source notices.

## SameBoy

- Project: SameBoy
- Author: Lior Halphon
- Upstream: https://github.com/LIJI32/SameBoy
- Location: git submodule at `Packages/EmulatorKit/Dependencies/SameBoy`
- Pinned commit: `213a12ce93d66b105a113debd9396306066a7cfc` (`v1.0.3-5-g213a12c`)
- Why this commit and not the `v1.0.3` tag: the five commits after the tag include upstream
  `21b0dd3`, which fixes the `object_low_line_address` mask in `sanitize_state`. In `v1.0.3`
  that mask does not bound the field, so loading a corrupt save state can read past the end of
  VRAM. The other four commits change only the Cocoa frontend and Workboy emulation, which Press
  Any does not compile or use. Move to a release tag once one contains this fix.
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

## LCD display filters

- Code: `App/Gameplay/Shaders.metal`, the LCD 1x and LCD 3x filters. Press Any's own shader code,
  written for this project. No code is copied from the shaders below; their formulas differ.
- Inspiration: the LCD shaders in libretro's slang-shaders collection
  (https://github.com/libretro/slang-shaders), RetroArch's shader set. `lcd3x`, by Gigaherz, is
  the closest. Its header says "License: Public domain". The collection's other LCD shaders, such
  as `lcd-grid-v2`, carry no author or license header, and Press Any does not use them.
- Credit: the app credits the libretro shaders in Acknowledgements even though nothing is copied
  and `lcd3x` asks for none. The author of any shader that ships later is credited the same way
  (see AGENTS.md).

## In the app

Settings > Acknowledgements lists the code, artwork and data used in the app. SameBoy's,
GRDB.swift's and Corporatus's notices are bundled in `App/Acknowledgements/`; gbtoolsid, which is in
the public domain, No-Intro and the libretro LCD shaders get a credit.

## Updating a dependency

Updating a pin is an explicit change: update it, copy its license into `App/Acknowledgements/`
if it changed, run the platform-independent tests and the device checks in
`docs/mvp-verification.md`, and record the reason here. A SameBoy update is a
core migration candidate: existing Builds keep their pinned core until they are migrated
deliberately.


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
