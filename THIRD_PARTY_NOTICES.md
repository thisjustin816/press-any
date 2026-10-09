# Third-Party Notices

Press Any depends on these third-party open-source projects. Dependencies are pinned without
copying source snapshots into this repository. Adapted code and data carry their source notices.

## SameBoy

- Project: SameBoy
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
  bundled or adapted. The twelve boot palette choices copy RGB555 values and combination
  mappings from `BootROMs/cgb_boot.asm` into `SameBoyBridge/SameBoyBootPalettes.h`, which carries
  the Expat notice. Their background/OBJ0/OBJ1 use is checked against Pan Docs:
  https://gbdev.io/pandocs/Power_Up_Sequence.html#compatibility-palettes.
  Press Any's controller layouts and artwork are its own.
- License: Expat (MIT-style); see the submodule's `LICENSE`.

## GRDB.swift

- Project: GRDB.swift
- Upstream: https://github.com/groue/GRDB.swift
- Pinned version: 7.11.1
- Usage: SQLite persistence through Swift Package Manager.
- License: MIT; see the pinned upstream package for the authoritative license text.

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

## In the app

Settings > Acknowledgements lists each project whose code ships in the app. SameBoy's and
GRDB.swift's licenses are bundled verbatim from `App/Acknowledgements/`; gbtoolsid, which is in
the public domain, and No-Intro get a credit.

## Updating a dependency

Updating a pin is an explicit change: update it, copy its license into `App/Acknowledgements/`
if it changed, run the platform-independent tests and the device checks in
`docs/mvp-verification.md`, and record the reason here. A SameBoy update is a
core migration candidate: existing Builds keep their pinned core until they are migrated
deliberately.
