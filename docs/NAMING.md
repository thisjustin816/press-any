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

## Wordmark

The wordmark is the product name in heavy italic system type with slight tracking, the first
letter of its last word (the "A" in "Any") in the magenta of a Game Boy A button. The rest is
charcoal on light backgrounds and gray on dark ones:

| | Light | Dark |
|---|---|---|
| Letters | `#323235` | `#808086` |
| Accent letter | `#962C64` | `#A43E74` |

In the library's title and on the welcome screen, the letters shade from lighter at the top to
darker at the bottom, like the face of the controller's menu button, around those colors:

| | Light | Dark |
|---|---|---|
| Letters | `#55555A` to `#202022` | `#9C9CA2` to `#6C6C72` |
| Accent letter | `#B34680` to `#7C1E50` | `#BC568C` to `#8C2E60` |

`AppBrand.Wordmark` in `App/AppBrand.swift` is its one definition, built from the display name:
`WordmarkView` shows it in SwiftUI (the library's title, shrinking to fit beside toolbar buttons
that grow with larger text rather than cutting off letters), and the on-screen controller presses it
into the menu button at the bottom, in the controller theme's colors with a darker shade under
each letter's top edge and a light line along its bottom edge. Placeholder cartridges in the
library press the name, in capitals, into their plaque the same way.

## App icon

The app icon is a Game Boy A button seen from 45 degrees above the body, 25 degrees round from
bottom center to the right: a magenta button standing in a recess in the Classic controller's
gray body, its top face and side wall both showing, with an A engraved upright in the face, so it
slants across it. A Dark variant sits on the Dark body, and a grayscale Tinted variant serves
iOS 18. `Scripts/app-icon/icon.html` draws it and `Scripts/render-app-icon.sh` renders it into
`App/Assets.xcassets/AppIcon.appiconset`. It carries no name, so a rename leaves it unchanged.

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
   wordmark follows it, accenting the first letter of the new name's last word.
2. If the technical name also changes: the project `name`, target, scheme and `PRODUCT_NAME`
   in `project.yml`, `PROJECT_NAME` in the `Makefile`, and the `App/` entry point and
   `AppTests/` file names.
3. The bundle identifier only with a deliberate decision: a new identifier is a new app to iOS,
   with its own sandbox, so existing installs keep their data under the old identifier.
4. Prose in the living docs: `README.md`, `AGENTS.md`, `THIRD_PARTY_NOTICES.md`,
   `docs/device-build.md`, `docs/mvp-verification.md`,
   `Packages/EmulatorKit/Sources/SameBoyAdapter/Resources/BootROMs/README.md` and this file.
