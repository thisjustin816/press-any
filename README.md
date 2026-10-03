# Press Any

Press Any is an iPhone-first Game Boy and Game Boy Color emulator for players and for people
making Game Boy games. Its library keeps one Game across every ROM revision, patch and hack.

## Features

Games hold Builds (ROM revisions, patched versions and hacks), and Save Profiles hold battery
saves that Builds can share or copy. A save state belongs to the exact Build, profile and core
version that made it.

Importing a ROM analyzes it and shows a review before anything is committed, so duplicates are
caught and a new revision attaches to its existing Game. IPS and BPS patches create new Builds
while the source ROM and patches are kept, which lets a patched Build be rebuilt and checked
against its recorded hash.

Quick Play runs a ROM outside the library, optionally with a copy of a library save, and opens
straight on the game. A session can be promoted into the library later. Toolchain detection, a
Swift port of gbtoolsid, identifies GB Studio, GBDK, audio drivers and other tools a ROM was
built with.

Emulation is SameBoy behind a replaceable core boundary, with Metal video, audio, touch
controls, game controllers and rumble. Each Build stays pinned to the core version it first ran
on.

## Building

Clone with submodules, since SameBoy is one:

```bash
git clone --recurse-submodules https://github.com/thisjustin816/press-any.git
```

In an existing checkout, run `git submodule update --init`.

The Swift package tests run anywhere Swift 6.1 or later is installed:

```bash
make test-core
make test-sameboy-bridge   # Linux only
```

The app needs macOS with Xcode, XcodeGen and RGBDS (`brew install xcodegen rgbds`):

```bash
make bootstrap   # builds SameBoy's open boot ROMs and generates PressAny.xcodeproj
make test
```

To install it on your own iPhone with a free Apple ID, follow `docs/device-build.md`.

## Documentation

- `docs/specs/`: the product and MVP specifications, the original decision log, and the
  decisions approved after it.
- `docs/decisions.md`: decisions made since, newest first.
- `docs/acceptance-matrix.md`: the L1-L4 evidence levels CI and device checks use.
- `docs/ci.md`: what each CI job runs.
- `docs/NAMING.md`: product, technical and persistent names.
- `AGENTS.md`: rules for coding agents working in this repository.

## Dependencies

- [SameBoy](https://github.com/LIJI32/SameBoy), a git submodule at
  `Packages/EmulatorKit/Dependencies/SameBoy`. Only its core and open boot ROMs are built.
- [GRDB.swift](https://github.com/groue/GRDB.swift) through Swift Package Manager.
- [gbtoolsid](https://github.com/bbbbbr/gbtoolsid), ported to Swift; its tests run against the
  original in CI.

`THIRD_PARTY_NOTICES.md` records the pinned versions and their licenses.

## License

Press Any's own source is licensed under Apache-2.0 (`LICENSE`). Dependencies keep their own
licenses. The repository contains no game images, saves or Nintendo boot ROMs.
