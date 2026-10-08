# Continuous integration

Workflows live in `.github/workflows/`. Every action is pinned to a commit SHA, every
workflow runs with `contents: read`, and a fork pull request gets the same read-only token.
The one exception is TestFlight's tag job, which has `contents: write` and no secrets.
CI and iOS build skip a pull request or push that changes only `docs/` or Markdown files, so docs
merge without waiting on runners. Pull-request checks use no secrets. The TestFlight workflow,
which runs for pushes to `main` and when started by hand, uses repository secrets for Apple
signing and upload, as described in `docs/testflight.md`.

## Implemented

| Workflow | Job | What it runs |
|---|---|---|
| `ci.yml` | Package tests and headless SameBoy | `swift test` on the whole EmulatorKit package, which covers layers L1 to L3 of `docs/acceptance-matrix.md`, then `Scripts/test-sameboy-bridge-linux.sh`. A new test target runs without any change to the workflow |
| `ci.yml` | Toolchain detection matches gbtoolsid | `Scripts/test-toolchain-detection-differential.sh`: builds gbtoolsid at the ported revision, checks `GBToolsIDData.swift` regenerates unchanged, and requires the Swift port to match it on gbtoolsid's test ROMs and on generated ROMs |
| `ci.yml` | Repository hygiene | `Scripts/verify-repo-hygiene.sh` (no tracked game images, saves or generated Xcode projects; the ROMs in `TestROMs/roms/` are allowed only when `TestROMs/manifest.json` lists them with a matching SHA-256), `shellcheck` at error severity, the No-Intro generator's tests, and a warning when the bundled No-Intro data is more than 90 days old |
| `accuracy.yml` | Accuracy test ROMs | Only for changes to SameBoy, the bridge, the boot ROM script or the harness, since the pinned suites can't change a result otherwise; also by hand. Builds RGBDS for the boot ROMs, then `Scripts/test-accuracy-roms.sh`: fetches Blargg's tests and builds the Mooneye Test Suite at the commits game-boy-test-roms v7.0 uses, runs each through `SameBoyBridge` on the models the app uses (DMG-B and CGB-E) with SameBoy's boot ROMs, and fails when a result differs from `Scripts/tests/accuracy-expected.txt`. After an intended change, such as a SameBoy update, `--update` rewrites that file to commit with it |
| `ios-build.yml` | Xcode build, tests and Release archive | On one `macos-26` runner: `make bootstrap`, `make build`, `Scripts/verify-privacy-manifest.sh` (lints the privacy manifest and checks the built app carries it unchanged) and `make test`; `make test-package-ios`, the `EmulatorKit-Package` scheme's tests against Apple's Foundation; and, on pull requests and runs started by hand, a Release archive for a device with signing off, with the privacy check on the archived app, so a Release-only failure shows before a TestFlight upload. The package tests and the archive run even when the app's build or tests failed. On failure, a last step repeats only the Xcode error lines in the job summary |
| `ios-build.yml` | Shared ROM and patch UI flows | Pull requests and runs started by hand. `make test-share-ui`: installs a test-only sender, selects Press Any from the system share sheet, and checks GB import/cancellation, GBC Quick Play, IPS/BPS application, queued delivery and open Game Details refresh. Started by hand with `share_ui_controls`, it also runs the regression controls, which remove the refresh listener and game-menu pause hook separately and require the new-Build and menu-Resume assertions to fail. Logs, screenshots and xcresults are uploaded as `shared-file-ui-results` |
| `screenshots.yml` | Simulator screenshots (manual only) | Selects iPhone 14 Plus (default, verified 1284 × 2778 PNGs for Apple's 6.5-inch slot), iPhone 17 Pro Max (6.9-inch slot) or iPhone 17 Pro. Creates the simulator if needed, seeds the library from `TestROMs/`, captures the app, menu, and GB/GBC LCD 1×/3× effects, and uploads PNGs and logs as light/dark artifacts. See `docs/testflight.md` for downloading and uploading selected PNGs |
| `testflight.yml` | Archive and upload to TestFlight | Automatic for each push to `main` once iOS build and CI pass on it, skipping docs- and workflow-only pushes; manual from any repository branch. Sets What to Test from the commits since the previous upload and tags `main` uploads `testflight/<build>`. `make bootstrap`, then `Scripts/upload-testflight.sh`: validates the distribution certificate and App Store profile, signs a Release archive in a temporary keychain, verifies its privacy manifest, exports an IPA and uploads it with an App Store Connect team API key. Needs the six secrets in `docs/testflight.md`; uploads share one queue across branches |
| `release.yml` | Ship a GitHub release (published releases only) | Fills an empty release description with the changes since the previous release (the only job with `contents: write`, and it has no secrets). A pre-release on `main` adds its TestFlight build, the nearest `testflight/<build>` tag, to the group in the `TESTFLIGHT_PUBLIC_GROUP` variable and submits it for Beta App Review with the description as What to Test, using `Scripts/testflight-release.py`. A stable release names the build to submit to the App Store by hand |

The Linux Swift jobs run in the `swift:6.1.2-noble` image, whose tag is not pinned by digest.
The image has no SQLite headers, so each Swift job installs `libsqlite3-dev` first; GRDB needs
`sqlite3.h` on Linux.
Every job that builds the package checks out submodules, because SameBoy is one.

## Simulator coverage and device checks

`ios-build.yml` builds the app and runs the app and package tests on the iPhone 17 Pro
simulator. The hosted `PressAnyTests` launch the app and check its display name and bundled
licenses, toolchain labels, controller disconnect and touch-to-reveal behavior, frame pacing,
gameplay pause/lifecycle transitions (including frozen frame counts and explicit menu Resume), import review edits through database reopen, and Press Any Plus. The Plus purchase tests load `Config/PressAnyPlus.storekit`, which the test bundle carries, into an `SKTestSession`, so buying, restoring, refunds and a failed product load run on the simulator with no App Store account. Controller
and gameplay tests use simulated input or fake runtimes; they do not prove real hardware behavior.
The manual screenshot workflow also launches seeded gameplay and taps menus through UI tests.

The shared-file UI suite uses the existing original fixtures in `TestROMs/`, with a separate
Debug library for each test. Run `make bootstrap && make test-share-ui` on macOS; `DEVICE` can
select another simulator, and `SHARE_UI_CONTROLS=1` adds the regression controls. Each control
rebuilds the app, so they run only when asked: after changing the refresh listener, the game-menu
pause hook or the assertions that guard them. A push to `main` skips the suite, since its pull
request ran it. The sender is a separate test app and is excluded from the Release
app's scheme. These simulator flows still leave Files/browser variants and physical-iPhone
handoff in the device checklist.

On October 6, 2026, [run 37419621678](https://github.com/thisjustin816/press-any/actions/runs/37419621678)
passed all six shared-file UI scenarios on commit `8dd51ca`. Both controls reached their intended
assertions: removing the refresh listener failed the new-Build check, and removing the game-menu
pause hook failed the Resume check. Hosted app tests, iOS package tests and the unsigned Release
archive also passed; [Linux CI](https://github.com/thisjustin816/press-any/actions/runs/37419621685)
passed on the same commit.

Audio buffering has package tests, but the sound, latency, audio routes and interruptions still
need a physical iPhone. The unsigned archive job checks Release compilation and resources; it
does not install or run the app on a device.

Physical-iPhone verification is manual and is not part of any workflow. A green run of either
workflow is not the MVP device gate.

## Not built yet

`docs/product.md` (Automation) lists further workflows.
None exists, because each needs a generator, a data source or a rights decision that does not
exist yet, and a workflow that only prints success would be misleading:

- `no-intro-update.yml` is not going to be built: DAT-o-MATIC bans clients it takes for bots, so
  the No-Intro data is refreshed by hand (`docs/product.md`, Identity and naming).
- `shader-catalog-update.yml`, `openvgdb-update.yml`: need their generators and approved upstream
  sources. OpenVGDB stays disabled until its data license is established.
- `toolchain-fingerprints-update.yml`: `ci.yml` already checks the port against its pinned
  gbtoolsid revision. A workflow that moves the pin to a new release and opens a pull request is
  not built.
- `included-games-verify.yml`: needs the manifest schema and approved ROMs.
- `fixtures.yml`: needs the synthetic ROM and patch generators.
- `license-audit.yml`, `privacy-audit.yml`: need a dependency policy and the SBOM tooling.

Update workflows, when added, open pull requests and never merge or publish.
