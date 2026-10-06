# Continuous integration

Workflows live in `.github/workflows/`. Every action is pinned to a commit SHA, every
workflow runs with `contents: read`, and a fork pull request gets the same read-only token.
Pull-request checks use no secrets. The manually started TestFlight workflow uses repository
secrets for Apple signing and upload, as described in `docs/testflight.md`.

## Implemented

| Workflow | Job | What it runs |
|---|---|---|
| `ci.yml` | L1 domain and application | `swift test` filtered to `EmulatorDomainTests`, `EmulatorApplicationTests`, `EmulationCoreTests`, `EmulationSessionTests`, `GameplayInputTests`, `GameplayAudioTests`, `ImportingTests`, `PatchingTests`, `QuickPlayTests`, `ToolchainDetectionTests` |
| `ci.yml` | L2 storage and persistence | `AssetStorageTests`, `PersistenceGRDBTests`, `ArchitectureProofTests` |
| `ci.yml` | L3 headless SameBoy | `SameBoyAdapterTests` and `Scripts/test-sameboy-bridge-linux.sh` |
| `ci.yml` | Toolchain detection matches gbtoolsid | `Scripts/test-toolchain-detection-differential.sh`: builds gbtoolsid at the ported revision, checks `GBToolsIDData.swift` regenerates unchanged, and requires the Swift port to match it on gbtoolsid's test ROMs and on generated ROMs |
| `ci.yml` | All test targets are covered | `Scripts/verify-ci-test-coverage.sh` fails when a directory under `Packages/EmulatorKit/Tests/` is not named in `ci.yml` |
| `ci.yml` | Repository hygiene | `Scripts/verify-repo-hygiene.sh` (no tracked game images, saves or generated Xcode projects; the ROMs in `TestROMs/roms/` are allowed only when `TestROMs/manifest.json` lists them with a matching SHA-256) and `shellcheck` at error severity |
| `ios-build.yml` | Xcode simulator build and tests | `make bootstrap`, `make build`, `Scripts/verify-privacy-manifest.sh` (lints the privacy manifest and checks the built app carries it unchanged), `make test` on the `macos-26` runner; on failure, a last step repeats only the Xcode error lines in the job summary |
| `ios-build.yml` | Shared ROM and patch UI flows | `make test-share-ui`: installs a test-only sender, selects Press Any from the system share sheet, and checks GB import/cancellation, GBC Quick Play, IPS/BPS application, queued delivery and open Game Details refresh. A control removes the refresh listener and requires the new-Build assertion to fail. Logs, screenshots and xcresults are uploaded as `shared-file-ui-results` |
| `screenshots.yml` | Simulator screenshots (manual only) | Selects iPhone 14 Plus (default, verified 1284 × 2778 PNGs for Apple's 6.5-inch slot), iPhone 17 Pro Max (6.9-inch slot) or iPhone 17 Pro. Creates the simulator if needed, seeds the library from `TestROMs/`, captures the app and menu UI, and uploads PNGs and logs as light/dark artifacts. See `docs/testflight.md` for downloading and uploading selected PNGs |
| `ios-build.yml` | Package tests on the iOS simulator | `make test-package-ios`: the `EmulatorKit-Package` scheme's tests against Apple's Foundation, with the same failure summary |
| `ios-build.yml` | Unsigned Release archive | `make bootstrap`, a Release archive for a device with signing off, and `Scripts/verify-privacy-manifest.sh` on the archived app, so a Release-only failure shows before a TestFlight upload |
| `testflight.yml` | Archive and upload to TestFlight | Manual, from a repository branch including feature branches. `make bootstrap`, then `Scripts/upload-testflight.sh`: validates the distribution certificate and App Store profile, signs a Release archive in a temporary keychain, verifies its privacy manifest, exports an IPA and uploads it with an App Store Connect team API key. Needs the six secrets in `docs/testflight.md`; uploads share one queue across branches |

The Linux Swift jobs run in the `swift:6.1.2-noble` image, whose tag is not pinned by digest.
The image has no SQLite headers, so each Swift job installs `libsqlite3-dev` first; GRDB needs
`sqlite3.h` on Linux.
Every job that builds the package checks out submodules, because SameBoy is one.

Add each new test target to one of the layer filters in `ci.yml`; the coverage job fails until it
is listed.

## Simulator coverage and device checks

`ios-build.yml` builds the app and runs the app and package tests on the iPhone 17 Pro
simulator. The hosted `PressAnyTests` launch the app and check its display name and bundled
licenses, toolchain labels, controller disconnect and touch-to-reveal behavior, frame pacing,
gameplay pause/lifecycle transitions, and import review edits through database reopen. Controller
and gameplay tests use simulated input or fake runtimes; they do not prove real hardware behavior.
The manual screenshot workflow also launches seeded gameplay and taps menus through UI tests.

The shared-file UI suite uses the existing original fixtures in `TestROMs/`, with a separate
Debug library for each test. Run `make bootstrap && make test-share-ui` on macOS; `DEVICE` can
select another simulator. The sender is a separate test app and is excluded from the Release
app's scheme. These simulator flows still leave Files/browser variants and physical-iPhone
handoff in the device checklist.

Audio buffering has package tests, but the sound, latency, audio routes and interruptions still
need a physical iPhone. The unsigned archive job checks Release compilation and resources; it
does not install or run the app on a device.

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
