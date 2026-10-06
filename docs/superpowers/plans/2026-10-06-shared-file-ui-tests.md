# Shared File UI Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exercise ROM and patch sharing through the system share sheet, queued delivery and refreshing open Game Details.

**Architecture:** A simulator-only sender app presents `UIActivityViewController` with existing licensed fixtures. XCUITest chooses Press Any from that sheet and follows the production UI. Each test launches Press Any with a Debug-only UUID selecting an isolated library.

**Tech Stack:** Swift 6, iOS 17, XCTest/XCUITest, XcodeGen, GitHub Actions macOS 26.

**Spec:** `docs/decisions.md`, "Shared ROMs and patches, and Playtiles direction zones"; `docs/mvp-verification.md`, file handoff and returning to Game Details.

## Global Constraints

- Minimum deployment target: iOS 17.
- Build ROM identity is immutable. Editing a patch stack produces a new Build/result.
- Source ROMs and source patches are preserved.
- Use the original fixtures already recorded in `TestROMs/manifest.json`.
- No signing secrets, network downloads or fixture sender in the Release app.

### Task 1: Simulator sender and UI scenarios

**Files:** Create `ShareTestSender/ShareTestSender.swift`, `ShareUITests/SharedFileUITests.swift`, `Scripts/test-share-ui.sh`; modify `project.yml`, `App/AppContainer.swift`, `Makefile`, `.github/workflows/ios-build.yml`.

**Interfaces:** Sender buttons are fixture filenames; `UIActivityViewController(activityItems: [url], applicationActivities: nil)` owns delivery. App isolation uses launch arguments `-UITestLibrary <UUID>`. The scheme is `PressAnyShareTests`; the CI command is `make test-share-ui`.

- [x] Add the sender and UI target, with the existing revision-pair ROM and IPS/BPS fixtures and dual-mode GBC ROM as sender resources.
- [x] Add `testSharedGBReviewCancellationAndImport`, `testSharedGBCQuickPlayQueuesROMUntilSessionCloses`, `testSharedIPSRefreshesOpenGameDetails`, `testSharedBPSRefreshesOpenGameDetails`, `testPatchWaitsForLibraryGameplayToClose`, and `testSharedPatchCancellationKeepsOriginalBuild`.
- [x] Install the sender on the selected simulator, then run `xcodebuild test -scheme PressAnyShareTests -parallel-testing-enabled NO` and retain the xcresult.
- [x] Run syntax parsing, shellcheck, YAML validation and repository hygiene before pushing the tests to PR #18.

### Task 2: Coverage proof and documentation

**Files:** Modify `docs/ci.md`, `docs/mvp-verification.md`; update this plan's checkboxes.

**Interfaces:** The UI CI job saves green and regression-control results. The control removes only Game Details' `.libraryDidChange` receiver and runs `testSharedIPSRefreshesOpenGameDetails`, requiring that specific test to fail its new-Build assertion.

- [ ] Run the complete simulator suite and resolve any failures.
- [ ] Run the regression control with the listener removed, check the named assertion failure, and restore the source with a shell trap.
- [ ] Document simulator evidence and keep the physical-device checklist pending.
- [ ] Commit and push the final test and documentation changes; report the CI run and its actual results.
