# Build Menu and Scroll Cues Implementation Plan

**Goal:** Use the approved named Build action groups and show when app-owned lists have more content below.

**Architecture:** Keep native context menus and existing action handlers. Apply one shared SwiftUI modifier to every List, Form and vertical ScrollView. Use scroll geometry on iOS 18 and later, with a UIKit observation bridge for iOS 17.4.

**Tech Stack:** Swift 6, SwiftUI, UIKit, XCTest.

**Spec:** Owner-approved concept mockup, `docs/product.md`, Library and presentation and Accessibility.

## Global Constraints

- Minimum deployment target: iOS 17.4.
- Preserve every Build action and its eligibility conditions and confirmations.
- Keep Play direct. Use Play Options, Build Preferences, ROM and Patches and Organize.
- Show a bottom fade and chevron only while content remains below; never intercept scrolling or row taps.
- Cover lists, forms, the library grid, onboarding and license text. Keep text editors' own scrolling behavior.
- Native system menus retain their own scroll behavior.
- Create no repositories and add no dependencies or deployment changes.

## Task 1: Approved menu

- [x] Generate and show a concept mockup; obtain the owner's review before changing grouping.
- [x] Group Start Over and Play with Save under Play Options.
- [x] Group preferred Build/Save, Base marking and Build Settings under Build Preferences.
- [x] Keep ROM and Patches intact; group rename and Make Separate Game under Organize.
- [x] Keep Play, Build Info, Cheats and Delete Build direct.
- [x] Extend the existing screenshot capture to show the named submenus.

## Task 2: Shared overflow cue

- [x] Add `App/UI/ScrollOverflow.swift` for inset-aware remaining-content calculation, and regression cases for fitting content, scrolling, bounce, insets and resizing.
- [x] Add `App/UI/ScrollOverflowCue.swift` with native scroll geometry, bottom masking and a passive chevron. Add `App/UI/ScrollOverflowObserver.swift` for the iOS 17.4 bridge and lifecycle tests.
- [x] Apply `.scrollOverflowCue()` directly to every app-owned List, Form and vertical ScrollView.
- [x] Reconcile the inventory with all modifier sites, including inline forms and shared settings pickers.
- [x] Update product, backlog and device checks to describe the implemented behavior and outstanding evidence.
- [x] Run portable calculation tests, Swift syntax parsing and repository hygiene/whitespace checks.
- [x] Compile and run UIKit tests on the macOS CI runner.
- [ ] Complete the screenshot suite, including the landscape Settings selector regression.

## Review evidence

The generated mockup is a concept, not a running app. The owner approved its grouping. Visual evidence for the implementation still requires an iPhone or simulator, including iOS 17.4 fallback behavior, bottom toolbars, keyboard presentation, Dynamic Type and VoiceOver.

- The five calculation tests passed against the production calculation source in an isolated Linux SwiftPM harness. Removing bounce handling in that harness failed the expected assertions; restoring it passed.
- All 38 changed or new Swift files passed Swift 6 syntax parsing. This is not Apple SDK type checking.
- Syntax-tree inspection found the modifier directly on all 49 scrollable bodies. Removing one nested form's modifier from the inspection input reported exactly one omission.
- `make test-core` passed: 551 XCTest cases with 33 skipped, plus 231 Swift Testing cases.
- Repository hygiene and whitespace checks passed.
- Xcode app compilation, app tests, package tests and the unsigned Release archive passed. All three observation tests and five calculation tests passed on the simulator.
- All five Build menu screenshot cases passed. The Settings screenshot shows the fade and chevron. The screenshot suite exposed a landscape Settings query matching multiple elements; it now requires one tappable match, and the full suite must pass before upload.
