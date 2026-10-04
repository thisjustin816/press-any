# Third-Party Notices

Press Any depends on these third-party open-source projects. None of their source is copied into
this repository.

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
  bundled or adapted; Press Any's controller layouts, artwork and colors are its own.
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
- Ported revision: `v1.5.5` (`cc211126d81514b3c3988ed77a529f3886bbd796`)
- Usage: `Packages/EmulatorKit/Sources/ToolchainDetection/GB` is a Swift port of its detection
  logic. `GBToolsIDData.swift` is generated from its `src/entry_names_*.h` signature tables by
  `Scripts/generate-gbtoolsid-data.py`; the `check_*` functions are translated by hand. The
  app links the port and runs it in process; no gbtoolsid source or binary ships, and the app
  never runs the gbtoolsid tool.
- Verification: `Scripts/test-toolchain-detection-differential.sh` builds gbtoolsid at the
  ported revision and requires the port to produce identical results on its test ROMs and on
  synthetic ROMs. The test ROMs are fetched at run time and never committed here.
- License: public domain, under the Unlicense (https://unlicense.org).

## Test ROMs

- Location: `TestROMs/`. Not part of the app or its tests' build.
- Original code and assets: MIT. The ROMs link the GBDK-2020 runtime (GPL v2 with a linking
  exception), and the GB Studio and ZGB ROMs link those engines (MIT). Each directory under
  `TestROMs/src/` carries the notices; `TestROMs/README.md` lists the versions.
- hUGEDriver (public domain) is fetched at a pinned commit by its ROM's build, not kept here.

## In the app

Settings > Acknowledgements lists each project whose code ships in the app. SameBoy's and
GRDB.swift's licenses are bundled verbatim from `App/Acknowledgements/`; gbtoolsid, which is in
the public domain, gets a credit.

## Updating a dependency

Updating a pin is an explicit change: update it, copy its license into `App/Acknowledgements/`
if it changed, run the platform-independent tests and the device checks in
`docs/mvp-verification.md`, and record the reason here. A SameBoy update is a
core migration candidate: existing Builds keep their pinned core until they are migrated
deliberately.
