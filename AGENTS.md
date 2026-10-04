# Press Any Agent Guide

This repository is the implementation of the Press Any iPhone-first GB/GBC emulator.
Read this file before making architectural changes.

## Source of truth

Read these documents in order:

1. `docs/specs/gb-emulator-mvp.md`
2. `docs/specs/gb-emulator-product.md`
3. `docs/specs/gb-emulator-decisions.md`
4. `docs/specs/gb-emulator-later-decisions.md`, which wins over the three above where they conflict
5. `docs/decisions.md`, decisions made since, newest first, which wins over all of the above

`docs/acceptance-matrix.md` defines the L1-L4 evidence levels that CI and the device checks use,
and `docs/mvp-verification.md` is the device checklist.

If implementation and specification disagree, do not silently redesign the product. Document the conflict and resolve it explicitly.

## Naming

The product is Press Any; `docs/NAMING.md` is the reference.

- The user-facing name comes only from `INFOPLIST_KEY_CFBundleDisplayName` in `project.yml`. Swift code uses `AppBrand.displayName`, never a string literal.
- `PressAny` is the technical name for the Xcode project, target, scheme and product. Package and module names stay brand-free.
- Never put the product name in persistent or compared values: platform IDs, storage paths, database identifiers, file formats, content hashes, or runtime labels.

## Non-negotiable architecture

- Minimum deployment target: iOS 17.
- iPhone-first. iPad-specific UX is later work.
- GB/GBC core: SameBoy 1.0.3. GBA is a later mGBA adapter, not a SameBoy replacement.
- Library identity is `Game -> Builds -> Save Profiles`; a ROM file is not a Game identity.
- Build ROM identity is immutable. Editing a patch stack produces a new Build/result.
- Battery saves belong to Save Profiles. Save states are scoped to exact Build + Save Profile + core serialization context.
- Quick Play is isolated from permanent library saves until explicit promotion.
- Source ROMs and source patches are preserved. Generated patched ROMs are rebuildable cache.
- Settings inherit App -> System -> Game -> Build, with only narrow Save Profile overrides.
- Persistence metadata uses GRDB/SQLite. Large binary assets stay on the managed filesystem.
- Domain/application packages must not depend on SwiftUI, UIKit, Metal, AVFoundation, GameController, GRDB, or SameBoy internals.
- Emulator-specific features belong behind core capability protocols; do not leak SameBoy types across the adapter boundary.

## Dependency policy

Do not permanently vendor third-party source snapshots into normal Git history.

- GRDB must be an SPM dependency pinned to the approved release.
- SameBoy is a Git submodule at `Packages/EmulatorKit/Dependencies/SameBoy`, pinned to the commit `THIRD_PARTY_NOTICES.md` records. Press Any compiles only its `Core/`, never SameBoy's iOS frontend. Changing the pin is an explicit core update; see "Updating a dependency" in `THIRD_PARTY_NOTICES.md`.
- Preserve upstream licenses and update `THIRD_PARTY_NOTICES.md` when dependencies change.

## Testing rules

- Do not commit copyrighted commercial ROMs or saves as fixtures. The original test ROMs in `TestROMs/` are the exception: built from the source beside them, each listed in `TestROMs/manifest.json`, which `Scripts/verify-repo-hygiene.sh` checks. Add a ROM there with its source, license and manifest entry, not anywhere else.
- Prefer generated/synthetic ROMs and generated IPS/BPS patches for automated tests.
- New domain/application behavior needs a test before or with implementation.
- Run `make test-core` after platform-independent changes.
- Run `make test-sameboy-bridge` after SameBoy bridge changes.
- On macOS, run the Xcode/device gates in `docs/mvp-verification.md` before broadening v1 scope.

## MVP gate

Do not expand into cloud/catalog/skin/shader breadth until the real-device MVP proof passes. The architecture proof must demonstrate:

- one Game surviving multiple ROM Builds;
- safe Save Profile sharing/forking;
- Build-specific state isolation;
- deterministic IPS/BPS derived-Build rebuilds;
- Quick Play isolation and promotion;
- Build promotion/merge preserving lineage and data.

## Product UX principle

Press Any has a high customization ceiling but must remain simple by default. Use progressive disclosure: presets first, then Customize/overflow/Advanced/Developer Mode. Do not expose a setting simply because an implementation knob exists.
