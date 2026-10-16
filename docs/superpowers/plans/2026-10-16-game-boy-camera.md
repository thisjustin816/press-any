# Game Boy Camera Implementation Plan

> **For agentic workers:** Execute inline in the current session. The named superpowers execution skills are unavailable in this workspace.

**Goal:** Supply iPhone camera images to camera cartridges in library play and Quick Play, including automatic Photo! DX RGB capture.

**Architecture:** Use `CameraCapability` behind the existing adapter boundary and serialize sensor updates through `SessionWorker`. Keep AVFoundation capture in the app target. Use the existing cartridge RAM, Save Profile and Quick Play paths for photos.

**Tech Stack:** Swift 6.1, C11, SameBoy 1.0.3, AVFoundation, XCTest.

**Spec:** `docs/product.md`, Game Boy Camera section; `docs/backlog.md`, v1.1 targets.

## Global Constraints

- Minimum deployment target: iOS 17.4.
- Domain/application packages must not depend on SwiftUI, UIKit, Metal, AVFoundation, GameController, GRDB, or SameBoy internals.
- Emulator-specific features belong behind core capability protocols; do not leak SameBoy types across the adapter boundary.
- Battery saves belong to Save Profiles.
- Quick Play is isolated from permanent library saves until explicit promotion.
- New domain/application behavior needs a test before or with implementation.
- No commercial ROMs or saves as fixtures.

### Task 1: Sensor contract and core integration

**Files:** `CameraCapability.swift`, `FutureCapabilities.swift`, `SameBoyAdapter.swift`, `SameBoyBridge.c`, `SameBoyBridge.h`, `EmulationSession.swift`, `QuickPlayRuntimeSession.swift`, `FakeEmulatorCore.swift`, and their package tests; `Scripts/tests/sameboy_bridge_smoke.c`.

**Interfaces:**

```swift
public struct CameraFrame: Equatable, Sendable {
    public init(luminance: Data) throws
    public init(rgb888: Data) throws
    public let rgb888: Data
}
public protocol CameraCapability: AnyObject {
    var hasCamera: Bool { get }
    func setCameraFrame(_ frame: CameraFrame?)
}
```

- [x] Add failing tests for exact sensor size and camera-cartridge detection. Confirm the missing API fails the build before implementation.
- [x] Implement a 128 by 112 RGB888 image, a grayscale convenience initializer, neutral-gray nil input and bridge-side byte-count checks.
- [x] Latch sensor input on a shot request and complete it after SameBoy sets its busy bit. Keep temporary display refreshes from changing the held shot.
- [x] Expose camera availability and frame updates through both session workers; test running, paused and stopped sessions.
- [x] Use a synthetic cartridge to check white, black and neutral-gray tiles, shot completion, input latching, paused previews and battery-save round trips.
- [x] Generate all SameBoy boot ROMs with `make bootroms`, then run `make test-core` and `ASAN_OPTIONS=detect_leaks=0 make test-sameboy-bridge`. LeakSanitizer cannot run under this executor's ptrace restriction; AddressSanitizer remains enabled.

### Task 2: Capture and gameplay lifecycle

**Files:** `App/Gameplay/GameplayCamera.swift`, `IPhoneCameraSource.swift`, `CameraFrameSampler.swift`, `GameplayDriver.swift`, `GameplayRuntime.swift`, `GameplayViewController.swift`, `project.yml`; `AppTests/GameplayCameraTests.swift`, `GameplayDriverTests.swift`, `GameplayLifecycleTests.swift`.

**Interfaces:** `GameplayCamera.select(_:)` requests access for an explicit choice. `setRunning(_:rotationAngle:)` follows gameplay activity. `CameraFrameBuffer` rejects frames from a stopped capture. The driver supplies its newest frame before stepping the core.

- [x] Implement Off, Rear Camera and Front Camera choices only for camera cartridges; start Off each session.
- [x] Request video permission only on selection. On denial, show where permissions can be checked. Discard replies after Off or close.
- [x] Configure and run capture on its own queue, with no audio input or automatic audio-session configuration. Center-crop BGRA to RGB888, apply interface rotation and mirror the front camera.
- [x] Stop hardware capture on pause and inactivity, retaining an unfinished RGB sequence. Off, camera selection, close and failure clear held images. Report interrupted or unavailable capture without ending gameplay.
- [x] Run the eight unchanged policy/sampling tests in a temporary Linux SwiftPM harness containing the app's platform-independent camera files. All eight pass.
- [x] Run the three driver tests alongside those eight tests in a Linux harness using their manual refresh source. This excludes the Apple display thread and platform session conformances; it verifies that absent new frames preserve a frozen capture, explicit clearing is serialized after in-flight frames, and save work does not block pacing.
- [x] Syntax-parse the app and integration-test files with `swiftc -frontend -parse`.
- [ ] On macOS, run `make generate`, `make build` and `make test` to typecheck Apple SDK calls and run the controller/driver integration tests.

### Task 3: Documentation and evidence

**Files:** `docs/product.md`, `docs/backlog.md`, `docs/mvp-verification.md`, `PRIVACY.md`.

- [x] Describe opt-in capture, fallback behavior, image lifetime and normal photo-save ownership. Move Camera to the backlog's Done line with Apple/device verification still pending.
- [x] Add unchecked device cases for permission, unavailable capture, both lenses, rotation, lifecycle, photo persistence, Save Profiles and Quick Play promotion.
- [x] Run `Scripts/verify-repo-hygiene.sh` and `git diff --check`.
- [ ] Complete the new physical-iPhone checks in `docs/mvp-verification.md`; Linux tests do not establish camera, audio-session or device behavior.

### Task 4: Photo! DX RGB handshake

**Files:** `SameBoyBridge.c`, `SameBoyBridge.h`, `SameBoyAdapter.swift`, `CameraCapability.swift`, `CameraFrameSampler.swift`, `IPhoneCameraSource.swift`, `GameplayDriver.swift`, `GameplayViewController.swift`; `Scripts/tests/sameboy_camera_rgb.c`, `Scripts/test-sameboy-bridge-linux.sh`, camera frame and sampling tests.

- [x] Add a failing synthetic camera ROM test for RGB input, version-1 requests and exact replies.
- [x] Preserve color through BGRA sampling and the capability/adapter boundary. Ordinary exposures derive brightness in the bridge.
- [x] Validate request magic, version, channel and fresh zero reply/reserved bytes at SRAM offset `0xF0`; acknowledge supported requests with `HOST`, version 1 and reserved 0. Leave other requests untouched.
- [x] Freeze the red exposure's RGB source through green and blue. A new or out-of-order sequence takes a fresh source. Brightness, invalid requests and resets end a sequence; Off clears held images. Display previews restore the full external capture context.
- [x] Verify the real fork artifact on CGB and AGB, including automatic capture, all saved channel pixels, group markers, stock checksums, battery reloads and every color-gallery image pixel. Record ROM hashes and exact input sequences in `docs/mvp-verification.md`.
- [x] Run the bridge and complete package tests plus the camera-policy/sampling harness; syntax-parse changed Apple files. Keep the Apple build and physical-device checks pending above.
