# Automatic Artwork Implementation Plan

> **For agentic workers:** Execute this plan task by task in the current session. The named superpowers execution skills are unavailable in this workspace.

**Goal:** Fill empty Game artwork after import from Libretro, with an app setting and a reviewed manual lookup.

**Architecture:** Use the existing No-Intro index to obtain canonical release names. A provider downloads one image, and the existing GameArtwork use case stores it with provenance in ManagedAsset.provenanceJSON. Automatic writes recheck the Game inside the existing transaction runner after the download.

**Tech Stack:** Swift 6.1, Foundation URLSession, ImageIO on Apple platforms, existing GRDB repositories, XCTest.

**Spec:** `docs/product.md`, Artwork section. This implements the Libretro slice; the other providers, generated fallback, typed image collection, crops and Build overrides remain separate work.

## Global Constraints

- Minimum deployment target: iOS 17.4.
- Persistence metadata uses GRDB/SQLite. Large binary assets stay on the managed filesystem.
- Domain/application packages must not depend on SwiftUI, UIKit, Metal, AVFoundation, GameController, GRDB, or SameBoy internals.
- New domain/application behavior needs a test before or with implementation.
- Run `make test-core` after platform-independent changes.
- Never bundle commercial game artwork as test fixtures or app resources.

### Task 1: Provider, matching and safe storage

**Files:**
- Create `Packages/EmulatorKit/Sources/EmulatorApplication/Ports/ArtworkProvider.swift` and `UseCases/FindMissingGameArtwork.swift`.
- Create `Packages/EmulatorKit/Sources/GameIdentity/ArtworkLookup+KnownDumps.swift`, `LibretroArtworkProvider.swift`, and `ArtworkHTTPClient.swift`.
- Modify `GameIdentity/KnownDumps.swift`, `EmulatorApplication/UseCases/GameArtwork.swift`, and `BuildOperations.swift`.
- Test in `Tests/GameIdentityTests/ArtworkLookupTests.swift`, `LibretroArtworkProviderTests.swift`, `ArtworkHTTPClientTests.swift`, and `Tests/EmulatorApplicationTests/FindMissingGameArtworkTests.swift`.

**Interfaces:**
- `ArtworkLookup(system: GameSystem, releaseNames: [String], inherited: Bool)` carries known identity.
- `ArtworkProvider.artwork(for: ArtworkLookup) async throws -> ProvidedArtwork?` returns the selected download or a miss.
- `FindMissingGameArtwork.execute(gameID: UUID, lookup: ArtworkLookup, expectedPreferredBuildID: UUID? = nil, trigger: Trigger = .automatic) async throws -> Bool` fills only an empty Game whose preference still matches the lookup and reports whether it wrote an image.
- `GameArtwork.set(..., provenance: ArtworkProvenance? = nil)` keeps current manual callers valid.

- [x] Write tests for canonical/region/revision matching, unknown/bad images, explicit base inheritance, URL character substitution, 404 fallback, HTTP failures, byte limits, cancellation, and provenance.

```swift
let lookup = ArtworkLookup(system: .gameBoy, releaseNames: ["Example (USA)"], inherited: false)
XCTAssertEqual(try index.artworkLookup(for: build, lookup: { _ in nil }), lookup)
XCTAssertFalse(try await automatic.execute(gameID: game.id, lookup: lookup)) // existing artwork
```

- [x] Run `swift test --package-path Packages/EmulatorKit --filter 'Artwork'` with the workspace toolchain; confirm the new API is missing before implementation.
- [x] Implement exact No-Intro matching with same-release revision fallback and recorded base inheritance. Substitute Libretro's reserved filename characters and percent-encode each URL component.
- [x] Implement an ephemeral URLSession transfer that refuses redirects and unexpected content types/statuses, checks Content-Length, bounds received bytes to `ImportSizeLimit.artwork.bytes`, and cancels with its caller.
- [x] Store provenance through the existing asset field and preserve it when artwork is copied. Recheck existing artwork within `LibraryTransactionRunner.run` after awaiting the provider.
- [x] Run the focused tests and inspect their results.

### Task 2: Import, setting and manual review

**Files:**
- Modify `App/AppContainer.swift`, `App/Import/ImportReviewViewModel.swift`, `SharedFileView.swift`, `App/Library/LibraryView.swift`, and `GameDetailView.swift`.
- Modify `App/QuickPlay/QuickPlayPromotionViewModel.swift` to trigger lookup only after promotion.
- Create `App/Library/ArtworkReviewView.swift`, `App/Settings/ArtworkSettingsView.swift`, and `EmulatorApplication/UseCases/AutomaticArtworkSetting.swift`.
- Modify `App/Settings/AppSettingsView.swift` and add import callback tests in `AppTests/ImportReviewTests.swift`.

**Interfaces:**
- `AutomaticArtworkSetting.load() throws -> Bool` defaults to true; `save(Bool)` uses app-scoped settings.
- `ImportReviewViewModel` accepts an optional post-import Build callback. It fires after successful import only when review did not choose artwork and the ROM is not an exact duplicate.
- `AppContainer` starts a lookup without awaiting it on the import path; library changes notify existing observers when art is stored.

- [x] Add tests proving the setting persists and the import callback skips duplicate, failed import and manually chosen artwork.

```swift
try AutomaticArtworkSetting(store: settings).save(false)
XCTAssertFalse(try AutomaticArtworkSetting(store: settings).load())
```

- [x] Wire all user import paths, including Quick Play promotion, to the lookup. Failures leave the imported ROM intact. Recheck the setting before writing an in-flight automatic result.
- [x] Add Settings > Library > Artwork and a Check for New Artwork action in the Game's artwork menu.
- [x] Show the fetched image beside existing art, require Use Artwork before replacement, and store nothing if the player cancels.
- [x] Syntax-parse changed app files here.
- [ ] Run Apple SDK, app tests and the device checklist on macOS/iPhone before claiming an iOS build or device validation.

### Task 3: Documentation and verification

**Files:** `docs/product.md`, `docs/backlog.md`, `docs/mvp-verification.md`, `PRIVACY.md`, `THIRD_PARTY_NOTICES.md`, `App/Settings/AcknowledgementsView.swift`, and `App/Plus/PlusRoadmap.swift`.

- [x] Describe the implemented slice and record remaining providers/typed artwork as missing or partial. Disclose the canonical-name request, provider/network identity, lack of ROM transfer, local storage and disable setting.
- [x] Credit Libretro contributors and original rights holders without claiming a blanket artwork license or bundling downloaded art.
- [x] Run `make test-core`, repository hygiene and third-party notices checks. Record Apple-only gaps accurately.
- [x] Review every changed file and the diff before shipping.

## Verification

- `make test-core`: 524 XCTest cases (32 platform-dependent skips), plus 230 Swift Testing tests; zero failures.
- Live URLSession downloader: valid 476,267-byte PNG from Libretro; clean exit.
- Repository hygiene, dependency notices and `git diff --check`: passed.
- Changed app and app-test files: Swift syntax parse passed. Apple SDK compilation, app-test execution, ImageIO checks and physical iPhone flows remain pending.

### Library-wide missing artwork

- [x] Add Find Missing Artwork to the library's More menu, with progress and cancellation.
- [x] Reuse the per-Game lookup and its protections for existing artwork, deliberate removals,
  changed preferences and in-flight player choices. An explicit search ignores the import setting.
- [x] Test the explicit-search policy with automatic artwork off, including a failing control.
- [x] Add App tests for library-wide progress, mixed artwork states, cancellation and an unreadable image.
- [ ] Verify the combined Apple checks and upload a new feature-branch TestFlight build.
