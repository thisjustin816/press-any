# Game Menu Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the gameplay wordmark visibly pressable and freeze gameplay when its menu opens.

**Architecture:** Keep the existing UIKit menu and layout hit areas. Render the wordmark on its actual UIButton; prepare the deferred menu by calling the existing explicit-player pause path. Resume remains an explicit action.

**Tech Stack:** Swift 6, UIKit, XCTest, GitHub Actions macOS simulators.

**Spec:** `docs/decisions.md`, 2026-10-06 game-menu button decision.

## Global Constraints

- Minimum deployment target: iOS 17.
- Swift code uses `AppBrand.displayName`, never a string literal.
- Preserve both controller layouts, themes, optional game-picture menu and physical-controller access.
- Reuse `GameplayPauseReasons.byPlayer`; do not introduce a second pause state machine.
- No commercial ROM fixtures; use existing licensed test ROMs.

---

### Task 1: Visible button and persistent menu pause

**Files:** Modify `App/Gameplay/GameplayViewController.swift`, `App/Gameplay/TouchControllerView.swift`, `App/Settings/AppSettingsView.swift`; test `AppTests/GameplayLifecycleTests.swift`, `ShareUITests/SharedFileUITests.swift`, `ScreenshotTests/MenuScreenshots.swift`, `Scripts/test-share-ui.sh`.

**Interfaces:** Consumes `pauseGameplay()`, `ControllerPalette.resolve(_:for:)`, `AppBrand.Wordmark.attributedString(size:ink:accent:)`. Produces `func prepareGameMenu() -> [UIMenuElement]` for the existing deferred menu.

- [ ] Add frame-count tests: start frames, open the menu, assert no further frames and cleared held input; invoke the returned Resume action and verify frames restart after scene interruptions.

```swift
let items = gameplay.prepareGameMenu()
XCTAssertFalse(gameplay.isRunningFrames)
let frozen = runtime.frames
RunLoop.current.run(until: Date().addingTimeInterval(0.06))
XCTAssertEqual(runtime.frames, frozen)
```

- [ ] Implement pause before preparing the existing menu; release controller input alongside touch input.

```swift
func prepareGameMenu() -> [UIMenuElement] {
    pauseGameplay()
    // Existing current-state menu actions follow.
}
```

- [ ] Move wordmark drawing onto the first menu UIButton. Give it a rounded gradient face, border, shadow and pressed feedback using the existing theme palette. Leave the optional picture target clear; update colors on theme changes.
- [ ] Extend the actual shared-GBC Quick Play UI test to tap Game Menu and require its Resume action before any app switch. Give the separate paused overlay the accessibility label Resume Game to distinguish it from the menu action.
- [ ] Run an additional UI regression control with only `pauseGameplay()` removed from `prepareGameMenu()`. Require failure at the new menu-pause assertion; restore all mutated sources on exit.
- [ ] Update Settings copy, decision and device checklist for a visible button and pause until explicit Resume.
- [ ] Parse Swift locally, run shellcheck and repository hygiene, commit and push PR #18.

```bash
swiftc -frontend -parse App/Gameplay/GameplayViewController.swift AppTests/GameplayLifecycleTests.swift
shellcheck Scripts/test-share-ui.sh
git diff --check
```

### Task 2: Native and visual verification

**Files:** Update this plan and `docs/mvp-verification.md` with observed evidence. Keep manual phone checks unchecked.

**Interfaces:** Consumes the feature branch and existing iOS CI/screenshot workflows. Produces run links and verified light/dark gameplay captures.

- [ ] Wait for hosted app, six share UI scenarios, both intentional-failure controls, package simulator tests and Release archive checks.
- [ ] Dispatch existing screenshots workflow on `fix/shared-files-playtiles`, `device=iPhone 14 Plus`, `appearance=both`, `roms=hero`, `shots=summary`, `text_size=default`, `import_rom=gbdk450-badsum.gb`.
- [ ] Inspect Game Boy and Playtiles button appearance plus paused menus, including physical-controller mode. Fix any observed failures and repeat affected checks.
- [ ] Record evidence, update PR #18 description and report results without merging or uploading a new TestFlight build.
