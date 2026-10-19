# Playtiles Placement and App Icon Implementation Plan

**Goal:** Place both landscape Playtiles beside the game picture, restore alignment on both sides,
and close the app icon's recessed well around its button. Each landscape guide keeps the exact
center indent nub, joined to two short rounded shoulders in one compact T-shaped guide.

**Architecture:** Keep the existing measured Playtiles geometry and menu sizing. Fit the picture
first, accounting for the full 40 mm tile bodies and guide thickness, then place them close to it
with at least eight points of clearance. Change the existing Canvas
icon renderer and regenerate the six colorways and their previews.

**Tech Stack:** Swift package geometry and XCTest, UIKit drawing, Canvas, Chromium.

**Spec:** `docs/product.md` (Landscape), `docs/NAMING.md` (App icon), and the owner's request to
move controls inward, restore the right alignment line and explore a quieter guide treatment.

## Global Constraints

- Minimum deployment target: iOS 17.4.
- Preserve portrait placement, measured physical control sizes, input mapping and the menu target.
- Keep both complete 40 mm controller bodies inside the phone's bounds.
- Preserve icon colors, button shape, shading, letter and Light/Dark/Tinted variants.
- Keep the original center nub and shorten each landscape alignment bar around it. Round the
  bar's ends and join it to the nub in one T shape. Each shoulder extends one nub-width from the
  nub, with a flat edge meeting the controller at the band's bottom edge before rotation.
- Stop after implementation and verification; leave changes uncommitted.

## Task 1: Anchor the Landscape Tiles to the Picture

**Files:**
- Modify: `Packages/EmulatorKit/Sources/GameplayInput/TouchControlLayout+PlaytilesLandscape.swift`
- Test: `Packages/EmulatorKit/Tests/GameplayInputTests/LandscapeLayoutTests.swift`
- Update: `docs/product.md`, `docs/backlog.md`

- [x] Replace edge-pinning assertions with picture-gap and full-body containment regressions.
  Keep the existing device sizes, scaling modes, safe-inset permutations and input tests.
  The defining assertions are:

  ```swift
  XCTAssertGreaterThan(guide.bar.width, guide.tab.width)
  XCTAssertEqual(layout.screen.x - leftTileEnd - guides[0].bar.height, 8, accuracy: 0.001)
  XCTAssertEqual(rightTileStart - layout.screen.x - layout.screen.width, 8, accuracy: 0.001)
  ```

- [x] Run the changed tests against the current implementation and confirm failure.
- [x] Fit the game picture using the current minimum tile margins and menu clearance, then set:

  ```swift
  let left = screen.x - 8 - bandWidth
  let right = screen.x + screen.width + 8 + tileAndGuideWidth - bandWidth
  ```

  Reuse the existing rotated control and center nub geometry. Draw the shortened rounded bar joined to the original center nub.
- [x] Run the layout and input regressions, then `make test-core` in the CI Swift toolchain.
- [x] Update the product and backlog descriptions to match placement and both compact connected guides.
- [x] Preview the compact T-shaped guides with the exact center nub and short joined shoulders.

## Task 2: Close the Icon Well

**Files:**
- Modify: `Scripts/app-icon/icon.html`
- Regenerate: all six `AppIcon*.appiconset` PNGs and their Light/Dark preview PNGs
- Update: `docs/NAMING.md`, `docs/product.md`, `docs/backlog.md`

- [x] Replace the trough's one-sided horizontal radius with a centered ellipse:

  ```javascript
  const nx = (column + 0.5 - 512) / radiusX;
  const floorX = (column + 0.5 - 512) / floorSize;
  ```

  Remove the trough-only left-side shading adjustments and blur pass.
- [x] Regenerate Light, Dark and Tinted assets for all six colorways through the existing renderer.
- [x] Inspect the icons and previews; verify dimensions, opaque Light/Dark icons and grayscale
  Tinted artwork with transparency. Confirm the well clears every image edge.
- [x] Update the icon descriptions, inspect the final diff and run repository hygiene checks.

## Verification Limits

Windows cannot run Xcode or physical iPhone checks. Package tests and browser-rendered artwork
provide local evidence; controller attachment, phone cutouts and guide appearance need device review.

## Task 3: Disable Playtiles on Incompatible Phones

**Goal:** Keep the app usable on every supported iPhone while preventing selection of a physical
layout that does not fit. The iOS 17.4 floor includes the 2020 and 2022 iPhone SE.

**Files:**
- Modify: `Packages/EmulatorKit/Sources/GameplayInput/TouchControlLayout.swift`
- Test: `Packages/EmulatorKit/Tests/GameplayInputTests/ControllerLayoutTests.swift`
- Create: `App/Gameplay/ControllerLayoutAvailability.swift`
- Test: `AppTests/ControllerLayoutAvailabilityTests.swift`
- Modify: `App/Screenshots/ScreenshotScene.swift`, `ScreenshotTests/MenuScreenshots.swift`
- Modify: `App/AppContainer.swift`, `App/Settings/AppSettingsPages.swift`,
  `App/Settings/ScopedSettingsView.swift`
- Update: `docs/product.md`, `docs/backlog.md`, `docs/mvp-verification.md`

**Interfaces:** Extend the existing gameplay resolver with a device fit result:

```swift
public func forGameplay(controllerConnected: Bool, playtilesSupported: Bool = true) -> Self {
    controllerConnected || !playtilesSupported ? .gameBoy : self
}
```

**Hardware fit rule:** Enforce the manufacturer's 68 mm active screen width requirement. For
supported iPhone display classes, require a shorter native screen edge of at least 1242 pixels
(the 68.9 mm-wide XS Max class at 458 ppi). This excludes SE, mini and narrower regular-size
phones. Use the scene's `screen.nativeBounds`, so neither rotation nor Display Zoom changes fit.
This identifies current screen classes and does not directly measure the display in millimeters.

- [x] Add a regression covering both stored styles, incompatible hardware, a connected controller,
  and restoration on compatible hardware. Confirm the unchanged API rejects the new fit argument.
- [x] Add the fit argument to `forGameplay` and pass the shared device result through both launch
  resolution paths, including inherited settings and Quick Play. Preserve stored choices.
- [x] Disable the Playtiles option in both existing pickers. Keep inheritance available so the user
  can clear overrides; guard selection against unavailable explicit values. Explain that Game Boy
  controls are used when Playtiles does not fit.
- [x] Cover hardware availability independently of rotation and Display Zoom using native screen
  geometry. Record the selected hardware fit rule alongside the implementation and its tests.
- [x] Keep the Debug screenshot override subject to hardware fit. Skip the two-tile screenshot
  check on narrower simulators so a Game Boy fallback is not counted as Playtiles evidence.
- [x] Run the focused package regressions and `make test-core` in the existing Linux container.
- [x] Update the product description, backlog and device checklist with the compatibility behavior.
  Xcode settings and launch integration checks remain device/macOS gates.
