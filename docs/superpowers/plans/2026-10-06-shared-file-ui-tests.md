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

- [x] Run the complete simulator suite and resolve any failures.
- [x] Run the regression control with the listener removed, check the named assertion failure, and restore the source with a shell trap.
- [x] Document simulator evidence and keep the physical-device checklist pending.
- [x] Commit and push the final test and documentation changes; report the CI run and its actual results.

## Verification evidence

- [iOS run 37405980704](https://github.com/thisjustin816/press-any/actions/runs/37405980704),
  commit `6708085`: all six share-sheet UI scenarios passed on iPhone 17 Pro. The control
  removed the refresh listener and failed the IPS test at the missing new-Build assertion.
  The script restored the source and the job passed, retaining both result bundles.
- All 31 hosted app tests, iOS package tests and the unsigned Release archive passed on that
  commit. [Linux CI 37405980652](https://github.com/thisjustin816/press-any/actions/runs/37405980652)
  passed too.
- Swift syntax parsing, shellcheck, actionlint, YAML validation, repository hygiene and
  `git diff --check` passed. A cleanup smoke check confirmed that repeated runs remove only
  their named result bundles and stale control log while retaining DerivedData and unrelated files.
- Physical-iPhone checks in `docs/mvp-verification.md` remain pending.
