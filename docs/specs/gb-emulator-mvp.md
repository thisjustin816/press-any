# GB Emulator: MVP Architecture Proof Specification

## Purpose
Build a narrow iPhone-first MVP that proves the product's defining mechanic: one persistent Game can own multiple immutable Builds and multiple reusable Save Profiles, while SameBoy provides accurate GB/GBC emulation behind a replaceable core adapter.

This is an architecture proof, not the public v1. Do not implement cloud/community/skin/shader breadth until the model below is proven with automated tests and real ROM workflows.

## Product invariant
**A ROM file is never the library identity.**

The identity hierarchy is:

`Game -> Builds -> launch context(Build + SaveProfile + pinned CoreVersion)`

A Game survives ROM replacement, patching, version changes, region/revision variants, and Build promotion/merging.

## MVP platform and stack
- iPhone-first, iOS 17+.
- Swift for app/application layers.
- SwiftUI for library/settings/import review; UIKit/Metal gameplay host where appropriate.
- GRDB + SQLite for metadata and relationships.
- Managed filesystem for ROMs, patches, saves, states, screenshots, and other binary assets. Do not put ROM/save/state blobs in SQLite.
- SameBoy library/core for GB/GBC.
- Metal rendering; low-latency adaptive audio.
- Apple GameController for physical controllers.
- SHA-256 content identity for managed binary assets; preserve source filename/provenance separately.

## Architecture rules
1. SameBoy is behind `EmulatorCore`; app/domain code must not depend on SameBoy structs.
2. Core capabilities are separate interfaces rather than one giant mandatory protocol.
3. Domain/application layers do not depend on SwiftUI/UIKit/GRDB/SameBoy.
4. Import is staged: `Analyze -> ImportPlan -> Review -> transactional Commit`.
5. Existing Build identity is immutable. Changing ROM bytes or patch recipe creates a new Build.
6. Source ROMs and source patches are irreplaceable managed assets. Generated patched ROMs are rebuildable cache.
7. Save states are exact-context artifacts: Build + SaveProfile + core/core-serialization version. Never share a state across Builds.
8. Battery saves belong to Save Profiles and may be shared by compatible Builds.
9. Quick Play is isolated from the permanent library until explicitly promoted.
10. Prefer simple defaults and progressive disclosure; the MVP need not expose every future setting.

## Proposed module boundaries
- `Domain`: Game, Build, BaseBuild relationship, SaveProfile, PatchRecipe, AssetIdentity, CorePin, settings keys.
- `Persistence`: GRDB repositories/migrations and filesystem asset store.
- `Importing`: analyzers, identity matching, ImportPlan, ImportReview model, commit transaction.
- `Patching`: IPS/BPS engines and recipe builder.
- `Emulation`: core protocols, SameBoy adapter, session coordinator, lifecycle autosave.
- `Rendering`: Metal framebuffer presentation.
- `Audio`: adaptive audio output.
- `Input`: touch actions, GameController mapping, haptics/rumble routing.
- `LibraryUI`: grid/list, Game detail, Build and Save Profile management.
- `QuickPlay`: temporary workspace and promotion.

## Core interfaces
Implementations may refine the Swift syntax but must keep these boundaries:

```swift
protocol EmulatorCore {
    var identifier: CoreIdentifier { get }
    var version: CoreVersion { get }
    var supportedSystems: Set<GameSystem> { get }

    func loadROM(_ rom: Data, configuration: CoreConfiguration) throws
    func start() throws
    func pause()
    func resume()
    func reset() throws
    func stop()

    func setInput(_ input: EmulatorInputState)
    func setSpeed(_ speed: EmulationSpeed)

    func loadBattery(_ data: Data?) throws
    func batteryData() throws -> Data

    func serializeState() throws -> Data
    func deserializeState(_ data: Data) throws
}

protocol RewindCapability { /* configure/push/rewind contract */ }
protocol RumbleCapability { /* amplitude callback */ }
protocol CheatCapability { /* later v1 surface */ }
protocol MemoryAccessCapability { /* later v1 surface */ }
protocol RTCCapability { /* later v1 surface */ }
protocol LinkCableCapability { /* future */ }
protocol CameraCapability { /* future */ }
protocol PrinterCapability { /* future */ }
```

Do not force future mGBA to emulate SameBoy-specific APIs. Capability absence must be representable.

## Data model
### Game
Stable UUID. User-facing identity. Required fields include primary title, optional aliases, system family, preferred Build ID, preferred Save Profile ID, created/modified timestamps, and metadata provenance/override records.

### Build
Stable UUID, `gameID`, system, concise display name, immutable ROM content hash, source kind (`importedROM` or `patchRecipe`), region/language/revision/version metadata, optional parent Build lineage, optional Base Build marker, preferred Save Profile ID, pinned core ID/version after first launch, and provenance.

Import suggests region, language, revision and numeric version from recognized filename tags;
a nonzero header revision is a fallback. Review can correct or clear these fields before commit,
and Technical Info shows the stored values. Unknown tags are not guessed. Quick Play promotion
uses the original picked filename. Duplicate imports do not overwrite existing Build metadata
(`docs/decisions.md`, 2026-10-05).

A Game may have multiple Base Builds for revisions/regions.

### SaveProfile
Stable UUID, Game association, display name, optional icon/badge, current battery-save asset, optional ancestry (`copiedFromProfileID`), RTC context where required, aggregate play statistics, and narrow playthrough-specific settings.

Save Profiles are manually creatable by blank save, duplicate, `.sav` import, or Quick Play promotion.

### SaveState
Stable UUID, Build ID, Save Profile ID, core ID/version, state serialization version, screenshot asset, timestamp, playtime, optional label, state asset hash. States never cross Build boundaries.

### PatchRecipe
Stable UUID, exact Base Build/hash, ordered IPS/BPS patch assets, resulting ROM hash. Editing order/enabled state creates a new Build/recipe result.

### ManagedAsset
Content hash, kind, byte length, managed relative path, original filename, import provenance, integrity status. Source assets and cache assets must be distinguishable.

## Filesystem policy
Use a managed root with content-addressed or otherwise collision-safe paths. Keep metadata paths relative and never rely on an external Files URL remaining available.

Suggested categories:
- source ROM blobs
- source patch blobs
- generated ROM cache
- battery saves
- save states
- state thumbnails
- Quick Play workspaces

Writes to saves/state metadata must be atomic. Never overwrite the only known-good source save as part of migration/testing.

## Import MVP
Supported direct files: `.gb`, `.gbc`, `.sav`, `.ips`, `.bps` where context makes association possible. Archive support is post-MVP.

For ROM import:
1. Copy/read into staging.
2. Hash before permanent mutation.
3. Parse GB header and filename metadata best-effort.
4. Check exact duplicate content.
5. Suggest existing Game using exact identity/known relationship first, then conservative heuristics.
6. Produce ImportPlan.
7. User chooses new Game vs Add Build where ambiguity exists.
8. Commit DB + files transactionally; rollback staged assets on failure.

Exact duplicate ROM must not create a second blob or Build accidentally.

## Build operations MVP
- Add imported ROM as Build of existing Game.
- Set Preferred Build.
- Mark one or more Base Builds.
- Promote Build to separate Game: Move or Copy, default Move.
- Merge standalone Game into another Game: Move or Copy Builds with review.
- Preserve lineage and Build-scoped data.
- Concise Build names; structured metadata remains separate.

## Patch MVP
- IPS and BPS only.
- Preserve original patch and exact base reference.
- Validate expected base where the format/evidence permits; mismatch requires explicit Apply Anyway.
- Patch result becomes a new immutable Build.
- Generated result may be cached, evicted, regenerated, and SHA-256 verified.
- Multiple patches may exist in ordered recipe data from day one, even if first MVP UI is intentionally simple.

## Save Profile MVP
- New blank profile.
- Duplicate profile.
- Import `.sav` into new or selected profile with explicit destructive confirmation where applicable.
- Build can remember preferred profile; otherwise fall back to Game preferred profile.
- Compatible Builds may intentionally share a profile.
- Save state artifacts remain Build-specific regardless of shared battery save.

For risky Build switches, prefer copying/forking a Save Profile over mutating the source.

## Lifecycle autosave MVP
- On normal background/exit/session switch: flush battery save atomically and update dedicated Auto State.
- Keep a small rolling Auto State history (product target: 5).
- Global autoresume default Always; support Always/Ask/Never policy model so later UI can override per Game/Profile.
- An Auto State is restored only while the profile's battery save is no newer than it (`docs/decisions.md`, 2026-10-03).
- On restore failure or incompatible context, boot normally and preserve the failed state for diagnosis rather than deleting it.
- Backgrounding pauses emulation/audio.

## Quick Play MVP
- Launch a ROM in a temporary sandbox without creating a permanent Game/Build.
- If user elects to use an existing Save Profile, copy its `.sav` into the sandbox; never write the source.
- Session-created battery save, state, screenshot/debug artifacts remain temporary.
- Default retention target: 24 hours.
- Promotion runs through Import Review and can create/add the Build and either keep existing save, replace after safety copy, or create a new Save Profile.
- Time to first frame is the primary metric (`docs/decisions.md`, 2026-10-03): read the image once, validate, copy and hash it, boot the core past the boot logo. No shaders, custom layouts, skins or other optional assets on the launch path; detection and metadata run after the first frame.

## Core pinning MVP
- First launch selects the current compatible SameBoy version and records it on the Build.
- Existing Build continues using its pin.
- The MVP need not ship multiple SameBoy binaries simultaneously unless required to prove rollback, but schema/API must support versioned pins and future migration checkpoints.

## Gameplay MVP
- Correct GB/GBC emulation via SameBoy.
- Metal video preserving native core timing.
- Low-latency adaptive audio.
- Basic touch D-pad/A/B/Start/Select.
- Sliding D-pad and A/B behavior.
- Light on-screen haptics by default; suppress when physical controller is active unless overridden.
- Bluetooth controller input; unexpected disconnect pauses and reveals touch controls.
- Cartridge rumble: controller preferred, iPhone fallback.
- Basic manual save/load state.
- Basic fast-forward sufficient to validate session architecture; final v1 presets are 1.5x/2x/3x/4x/8x/Unlimited.

## Settings MVP
Prove the resolver:

`App defaults -> System defaults -> Game overrides -> Build overrides`

Only store explicit overrides. UI must be able to report inherited source and reset to inherited. Save Profile has a narrow contextual override layer only for playthrough-specific settings in full v1.

## Library MVP
- Grid and list.
- Search by primary title at minimum; schema must support later FTS5 full metadata index.
- Game detail shows Builds and Save Profiles.
- Preferred Build one-tap Play.
- Build switch from Game detail.
- Basic manual artwork assignment is sufficient for architecture proof; automatic provider integration is not an MVP blocker.

## MVP non-goals
Do not block the MVP on: iCloud, Community Catalog, automatic artwork providers, No-Intro downloadable database, Delta/Manic skins, advanced layout editor, curated RetroArch shader library, AirPlay, manuals/docs, ZIP/7z, full cheats/memory search, link cable, Camera/Printer, GBA/mGBA, RetroAchievements, recording, full backup/migration ecosystem.

## Required tests
1. Import same ROM twice -> one content blob; no accidental duplicate Build.
2. Import modified ROM -> attach as second Build of same Game -> Game UUID unchanged.
3. Promote Build to Game and merge it back -> lineage/data preserved.
4. Multiple region/revision Base Builds coexist without hash confusion.
5. Duplicate Save Profile -> source bytes unchanged after target gameplay writes.
6. Two Builds intentionally share one Save Profile -> battery save shared; save states remain distinct.
7. Quick Play with copied library save -> source save hash remains unchanged after session.
8. Promote Quick Play -> selected save disposition produces expected profile without data loss.
9. Apply known IPS fixture -> expected output hash; source ROM and patch unchanged.
10. Apply known BPS fixture -> expected output hash; wrong base produces warning/error path.
11. Evict generated ROM cache -> launch rebuilds exact expected hash.
12. Background lifecycle -> atomic battery write + Auto State; restore resumes exact Build/Profile context.
13. Simulated failed DB/file commit -> no half-created Game/Build and no orphaned permanent asset.
14. Controller disconnect -> emulator pauses and touch controls become available.
15. Settings inheritance -> Build override wins; reset exposes Game/System/App value correctly.

## MVP acceptance scenario
The architecture proof is accepted when a tester can:

1. Import a clean Pokémon Crystal ROM as a Game/Base Build.
2. Play it and create/use a Save Profile.
3. Import a modified Crystal ROM as another Build without a duplicate library Game.
4. Reuse or fork the Save Profile intentionally and switch between Builds without save-state cross-contamination.
5. Apply a BPS patch to the preserved base ROM to create another Build.
6. Evict/rebuild the generated ROM and obtain the same hash.
7. Quick Play another test ROM using a copied save, create progress, then either discard it or promote it without modifying the source profile unexpectedly.
8. Promote a substantial hack Build to its own Game and later merge it back while preserving lineage.

If this flow is awkward or the data model needs exceptions, stop feature expansion and fix the architecture before proceeding to v1.
