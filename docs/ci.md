# Continuous integration

Workflows live in `.github/workflows/`. Every action is pinned to a commit SHA, every
workflow runs with `contents: read` and no secrets, and a fork pull request gets the same
read-only token.

## Implemented

| Workflow | Job | What it runs |
|---|---|---|
| `ci.yml` | L1 domain and application | `swift test` filtered to `EmulatorDomainTests`, `EmulatorApplicationTests`, `EmulationCoreTests`, `EmulationSessionTests`, `GameplayInputTests`, `ImportingTests`, `PatchingTests`, `QuickPlayTests`, `ToolchainDetectionTests` |
| `ci.yml` | L2 storage and persistence | `AssetStorageTests`, `PersistenceGRDBTests`, `ArchitectureProofTests` |
| `ci.yml` | L3 headless SameBoy | `SameBoyAdapterTests` and `Scripts/test-sameboy-bridge-linux.sh` |
| `ci.yml` | Toolchain detection matches gbtoolsid | `Scripts/test-toolchain-detection-differential.sh`: builds gbtoolsid at the ported revision, checks `GBToolsIDData.swift` regenerates unchanged, and requires the Swift port to match it on gbtoolsid's test ROMs and on generated ROMs |
| `ci.yml` | All test targets are covered | `Scripts/verify-ci-test-coverage.sh` fails when a directory under `Packages/EmulatorKit/Tests/` is not named in `ci.yml` |
| `ci.yml` | Repository hygiene | `Scripts/verify-repo-hygiene.sh` (no tracked game images, saves or generated Xcode projects; the ROMs in `TestROMs/roms/` are allowed only when `TestROMs/manifest.json` lists them with a matching SHA-256) and `shellcheck` at error severity |
| `ios-build.yml` | Xcode simulator build and tests | `make bootstrap`, `make build`, `make test` on the `macos-26` runner; on failure, a last step repeats only the Xcode error lines in the job summary |
| `screenshots.yml` | Simulator screenshots (manual only) | `Scripts/take-screenshots.sh`: seeds the library from `TestROMs/` (the hero ROMs, all of them, or chosen tags and filenames), opens each screen with the Debug-only `-ScreenshotScene` launch argument and uploads the PNGs as an artifact. By default it takes one of each screen, including gameplay with a controller attached; `every-rom` adds each ROM's game, Technical Info, and gameplay. Nothing asserts on them |
| `ios-build.yml` | Package tests on the iOS simulator | `make test-package-ios`: the `EmulatorKit-Package` scheme's tests against Apple's Foundation, with the same failure summary |

The Linux Swift jobs run in the `swift:6.1.2-noble` image, whose tag is not pinned by digest.
The image has no SQLite headers, so each Swift job installs `libsqlite3-dev` first; GRDB needs
`sqlite3.h` on Linux.
Every job that builds the package checks out submodules, because SameBoy is one.

Add each new test target to one of the layer filters in `ci.yml`; the coverage job fails until it
is listed.

## Not verified

`ios-build.yml` builds the app and runs the app and package tests on the iPhone 17 Pro
simulator, but nothing launches the app, so bundled resources, audio and controllers are compiled
rather than exercised. `PressAnyTests` only checks that the app reads its display name.

Physical-iPhone verification is manual and is not part of any workflow. A green run of either
workflow is not the MVP device gate.

## Not built yet

`docs/specs/gb-emulator-later-decisions.md` section 11 lists further workflows.
None exists, because each needs a generator, a data source or a rights decision that does not
exist yet, and a workflow that only prints success would be misleading:

- `no-intro-update.yml`, `shader-catalog-update.yml`, `openvgdb-update.yml`: need their generators
  and approved upstream sources. OpenVGDB stays disabled until its data license is established.
- `toolchain-fingerprints-update.yml`: `ci.yml` already checks the port against its pinned
  gbtoolsid revision. A workflow that moves the pin to a new release and opens a pull request is
  not built.
- `included-games-verify.yml`: needs the manifest schema and approved ROMs.
- `fixtures.yml`: needs the synthetic ROM and patch generators.
- `license-audit.yml`, `privacy-audit.yml`: need a dependency policy and the SBOM tooling.

Update workflows, when added, open pull requests and never merge or publish.
