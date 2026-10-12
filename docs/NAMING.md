# Naming

The product is **Press Any**. This file records which names are product branding, which are
technical identifiers, and which values must never carry a brand.

## Names in use

| Kind | Value | Where it lives |
|---|---|---|
| Product name (user-facing) | Press Any | `INFOPLIST_KEY_CFBundleDisplayName` in `project.yml`; the app reads it through `AppBrand.displayName` |
| App Store and TestFlight name | Press Any: Retro Game Emulator | App Store Connect, App Information. Up to 30 characters; Apple's search weighs the name heavily. Never names Game Boy, Nintendo or other trademarks |
| App Store subtitle | Every build, every save | App Store Connect, App Information. Up to 30 characters, shown under the name |
| Internal technical name | `PressAny` | Xcode project, app target, scheme and `PRODUCT_NAME` in `project.yml`; `PROJECT_NAME` in the `Makefile`; `App/PressAnyApp.swift` |
| Test target | `PressAnyTests` | `project.yml`, `AppTests/PressAnyAppTests.swift` |
| Bundle identifier | `com.thisjustin816.PressAny` | `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`; a developer can append a local `BUNDLE_ID_SUFFIX` in the git-ignored `Config/Signing.local.xcconfig` |
| Repository | `thisjustin816/press-any` | GitHub |
| Swift package and modules | `EmulatorKit`, `EmulatorDomain`, `AssetStorage`, ... | `Packages/EmulatorKit/Package.swift`; deliberately brand-free |

## Colors and wordmark

The app uses pink, navy and warm gray. Named colors in `App/Assets.xcassets` supply SwiftUI,
UIKit, the controller palettes and the icon renderer:

| Color | Light | Dark |
|---|---|---|
| Action accent (`AccentColor`) | `#B02165` | `#E26D9E` |
| Brand lettering (`BrandInk`) | `#282A63` | `#BCC0E8` |
| Controller and icon body (`BrandBody`) | `#D0CEC8` | `#24272F` |
| Filled buttons (`BrandButton`) | `#B02165` | `#B02165` |

Filled buttons and navy swipe actions keep white labels in both appearances. Text actions use
the brighter pink in Dark Mode. Native interface surfaces, primary and secondary text,
destructive actions and status colors follow iOS. Controller themes resolve their fixed
appearance independently of the library.

The wordmark is the product name in rounded Corporatus lettering with slight tracking. The first
letter of its last word (the "A" in "Any") is pink; the other letters use the brand ink.
`Scripts/render-wordmark.py` exports fixed outlined artwork from the display name, a separately
licensed font and the named colors. It requires Python with fonttools, reportlab and PyYAML:

```sh
python Scripts/render-wordmark.py /path/outside/the/checkout/corporatus_regular.otf
```

The font stays outside the repository and app. Settings > Acknowledgements and
`THIRD_PARTY_NOTICES.md` credit its authors and license. Regenerate the artwork when the display
name or brand colors change. `AppBrand.Wordmark` in `App/AppBrand.swift` sizes the artwork. `WordmarkView`
shows it in the library toolbar and welcome screen. The toolbar wordmark shrinks beside larger
buttons at accessibility text sizes. The controller presses it into its menu button, and
placeholder cartridges press the capitalized name into their plaque.

## App icon

The app icon is a smooth pink Game Boy-style button viewed nearly straight on, with a shallow
crown, lit rounded bevel and dark sidewall. A recessed well extends off the left edge and closes
with a rounded arch on the right. A navy A is centered below the button on the warm gray surface.
The Dark icon uses the dark body and lighter
lettering; the Tinted icon has grayscale artwork on a transparent background for iOS 18.

Berry, Grape, Teal, Kiwi and Dandelion use the same drawing with different button colors.
`Scripts/app-icon/icon.html` draws every variant; `Scripts/render-app-icon.sh` renders all six
icon sets and their Light/Dark settings previews. It requires Chromium and ImageMagick.
The icon carries no product name.

## Values that never carry a brand

These are stored, hashed or compared across versions, or are runtime names with no reason to
carry a brand. Renaming the product must not change them:

- Platform IDs: `gb`, `gbc`, and later `gba` (the raw values of `GameSystem`).
- The app data folder `Application Support/AppData/` and everything under it: `Library.sqlite`,
  `Source/`, `Cache/`, `UserData/`, `Temporary/QuickPlay/`.
- GRDB migration IDs (`mvp-v1`) and table names.
- Core IDs and serialization versions (`sameboy`, `sameboy-bess-v1`).
- File extensions and Quick Play workspace file names (`.rom`, `.sav`, `.state`,
  `session.json`, `rom.bin`, `battery.sav`, `autosave.state`).
- Content digests (SHA-256) and anything derived from file bytes.
- Runtime labels such as dispatch queue labels, Metal function names and thread-dictionary keys.

## Public identifiers still awaiting approval

These are not registered or reserved. Each needs an explicit decision before it is created:

- App Store Connect record, SKU and the App Store name "Press Any" (availability unchecked).
- Trademark clearance for "Press Any".
- Backend domain for the Community Catalog.
- App Group, iCloud container, Keychain access group, URL scheme and UTType identifiers. None
  exist yet; when added they derive from the bundle identifier.
- Signing team and provisioning.

The bundle identifier `com.thisjustin816.PressAny` is set in `project.yml` but has not been
registered with Apple.

## Renaming again

A future rename changes:

1. `INFOPLIST_KEY_CFBundleDisplayName` in `project.yml` (the only user-facing string). The
   wordmark export reads it, accenting the first letter of the new name's last word. Regenerate
   its artwork with `Scripts/render-wordmark.py`.
2. If the technical name also changes: the project `name`, target, scheme and `PRODUCT_NAME`
   in `project.yml`, `PROJECT_NAME` in the `Makefile`, and the `App/` entry point and
   `AppTests/` file names.
3. The bundle identifier only with a deliberate decision: a new identifier is a new app to iOS,
   with its own sandbox, so existing installs keep their data under the old identifier.
4. Prose in the living docs: `README.md`, `AGENTS.md`, `THIRD_PARTY_NOTICES.md`,
   `docs/device-build.md`, `docs/mvp-verification.md`,
   `Packages/EmulatorKit/Sources/SameBoyAdapter/Resources/BootROMs/README.md` and this file.
