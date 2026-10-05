# Shared Files and Playtiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open shared ROMs and patches through their existing review flows and prevent off-axis Playtiles presses from becoming accidental diagonals.

**Architecture:** Register imported document types and receive file URLs at the root scene. Copy each accepted regular file into bounded app-owned temporary storage before presenting review, and keep the source untouched. Playtiles uses a layout-specific angular threshold in the existing touch resolver.

**Tech Stack:** Swift 6, SwiftUI, UniformTypeIdentifiers, XCTest, existing EmulatorKit modules and GitHub Actions.

**Spec:** `docs/specs/gb-emulator-product.md` (Import architecture, Layouts/skins/touch), `docs/decisions.md` (Import hardening, Built-in controller layouts), and the owner's October 5 device report.

## Global Constraints

- Minimum deployment target: iOS 17.
- GB/GBC core: SameBoy 1.0.3.
- Library identity is `Game -> Builds -> Save Profiles`.
- A committed Build's image identity is immutable.
- Every file the player picks is treated as untrusted: ROMs at most 8 MB; patches at most 16 MB; accept regular files only.
- Preserve original filenames and source files; review before committing library changes.
- Skin-file importing requires the owner's format clarification. This plan covers the independent ROM/patch and built-in Playtiles changes.

## Task 1: Playtiles direction zones

**Files:**
- Modify: `Packages/EmulatorKit/Sources/GameplayInput/TouchControlLayout.swift`
- Modify: `Packages/EmulatorKit/Sources/GameplayInput/TouchInputResolver.swift`
- Test: `Packages/EmulatorKit/Tests/GameplayInputTests/TouchInputResolverTests.swift`

**Interfaces:**
- Consumes: `TouchControlLayout.make(_:width:height:safeTop:safeBottom:displayScale:scaling:pictureOpensMenu:)` and `TouchInputResolver.touchBegan(id:point:)` / `touchMoved(id:point:)`.
- Produces: `TouchControlLayout.dpadDiagonalRatio: Double`, default zero for existing layouts and 0.65 for Playtiles.

- [x] Add tests that press each cardinal direction at normalized dominant-axis 0.8 and perpendicular-axis ±0.4 on 375-, 393-, and 440-point phones. Assert exactly one direction. Sweep all four intentional diagonals, slide back to a cardinal direction and the center, and end the touch.
- [x] Run `swift test --package-path Packages/EmulatorKit --filter TouchInputResolverTests`; confirm the cardinal regression fails on the original resolver.
- [x] Add the layout property and use these thresholds before applying the signs of each axis:

```swift
let horizontalThreshold = max(deadZone, abs(normalizedY) * layout.dpadDiagonalRatio)
let verticalThreshold = max(deadZone, abs(normalizedX) * layout.dpadDiagonalRatio)
```

- [x] Run `make test-core`; verify intentional diagonals, sliding and multitouch continue to pass.
- [x] Commit the control fix and its tests together.

## Task 2: Incoming ROM and patch files

**Files:**
- Create: `App/Import/SharedFileInbox.swift`
- Create: `App/Import/SharedFileView.swift`
- Create: `App/Import/SharedPatchView.swift`
- Modify: `App/RootView.swift`
- Modify: `App/Import/ImportCoordinator.swift`
- Modify: `Config/PressAny-Info.plist`
- Test: `AppTests/SharedFileTests.swift`

**Interfaces:**
- Consumes: `ImportCoordinator.analyzeROM(at:targetGameID:)`, `ImportReviewViewModel`, `CreatePatchedBuild.execute(_:)`, and existing game/build repositories.
- Produces: `SharedFileInbox.receive(_ url: URL) throws -> SharedFile`, `discard(_ file: SharedFile)`, and `SharedFile` with `id`, `url`, `originalFilename`, and `kind` (`rom` or `patch`).

- [x] Write inbox tests using temporary generated files: preserve the filename and copied bytes after source deletion; reject remote URLs, unknown extensions, folders, symlinks and oversized files; remove only the staged copy on discard.
- [x] Implement receipt with security-scoped access and `ImportSizeLimit.rom` / `.patch`, then copy the accepted file to an isolated temporary directory.
- [x] Declare imported types for `.gb`, `.gbc`, `.ips`, and `.bps`, conforming to `public.data`, and register those types as documents the app can open. Use the same identifiers in the file pickers.
- [x] Route `.onOpenURL` at `RootView`; queue received files and present them when gameplay and the existing session sheets are closed. Keep queued files until review or Quick Play has consumed them.
- [x] Show ROM actions for Import to Library and Quick Play. Reuse Import Review and launch Quick Play only after the sharing sheet dismisses.
- [x] For a patch, require choosing its Game and base Build, then Apply Patch; preserve the existing explicit Apply Anyway path for a base mismatch. Notify the library after a successful commit.
- [ ] Add a hosted app test that verifies the shipped document-type declarations and UTTypes. Run iOS simulator tests and the Release archive through existing Actions CI.
- [ ] Commit the file handoff together with its tests and create a reviewable PR.

## Verification

- Confirmed the Playtiles regressions fail on the previous resolver (25 assertion failures), then pass with the change.
- `make test-core`: 221 XCTest tests, 3 boot-ROM-dependent tests skipped on this host, zero failures; all 14 Swift Testing tests passed.
- A local Swift 6 receipt harness compiled the actual inbox source and passed copy/filename/cleanup, remote/type/folder/link rejection, and ROM/patch size-limit checks. Linux uses a security-scope shim; Apple SDK behavior remains an iOS CI/device gate.
- Hosted app tests cover shared ROM review/Quick Play, patch creation, source preservation and the bundled document-type declarations.
- No skin importer is claimed or registered pending the format clarification.
