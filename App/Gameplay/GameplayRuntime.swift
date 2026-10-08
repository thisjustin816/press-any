import EmulationCore
import EmulationSession
import EmulatorDomain
import Foundation
import QuickPlay

/// Small app-facing runtime contract shared by permanent library sessions and Quick Play.
///
/// UIKit/Metal/GameController code depends on this protocol instead of knowing which
/// persistence model is underneath the emulation session.
protocol GameplayRuntime: AnyObject {
    var currentFrame: EmulatorVideoFrame? { get }
    var playtimeSeconds: Double { get }

    func stepFrame(input: EmulatorInputState) throws -> EmulatorVideoFrame
    func drainAudio(maxFrames: Int) throws -> [StereoSample]
    func setSpeed(_ speed: EmulationSpeed) throws
    func setDisplaySettings(colorCorrection: ColorCorrection, dmgPalette: DMGPalette) throws -> EmulatorVideoFrame?
    func consumeRumbleAmplitude() throws -> Double

    func pause() throws
    func resume() throws
    func background() throws
    @discardableResult func foreground(policy: AutoResumePolicy) throws -> Bool
    func stop(createAutoState: Bool) throws
    /// Retries a failed stop, or with `discardUnsaved` closes without the writes that failed.
    func stop(createAutoState: Bool, discardUnsaved: Bool) throws
    /// Writes the game's save once it changes, checking at most every few seconds of play.
    @discardableResult func flushBatteryIfChanged() throws -> Bool
    /// Starts the game again from its boot, keeping its save. Stop the frame loop first.
    func restart() throws
}

/// Library sessions also keep manual save states. Quick Play does not, since nothing in its
/// sandbox outlives the session unless it is promoted.
protocol SaveStateRuntime: GameplayRuntime {
    @discardableResult func saveCrashRecoveryIfDue() throws -> Bool
    func saveManualState(label: String?) throws -> SaveState
    func saveQuickState() throws -> SaveState
    func saveStates() throws -> [SaveState]
    func loadState(_ saveState: SaveState) throws
    /// Whether loading the state would take back a newer game save.
    func loadingWouldRollBackSave(_ saveState: SaveState) throws -> Bool
    /// Keeps the current save as "<profile> before loading state", then loads the state.
    @discardableResult func loadStateKeepingCopy(_ saveState: SaveState) throws -> SaveProfile
    func thumbnailData(for state: SaveState) -> Data?
}

extension EmulationSession: SaveStateRuntime {}
extension QuickPlayRuntimeSession: GameplayRuntime {}

final class GameplayInputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var touch = EmulatorInputState()
    private var controller = EmulatorInputState()

    func setTouch(_ input: EmulatorInputState) {
        lock.withLock { touch = input }
    }

    func setController(_ input: EmulatorInputState) {
        lock.withLock { controller = input }
    }

    func resetTouch() {
        setTouch(.init())
    }

    func resetController() {
        setController(.init())
    }

    func current() -> EmulatorInputState {
        lock.withLock {
            EmulatorInputState(
                up: touch.up || controller.up,
                down: touch.down || controller.down,
                left: touch.left || controller.left,
                right: touch.right || controller.right,
                a: touch.a || controller.a,
                b: touch.b || controller.b,
                start: touch.start || controller.start,
                select: touch.select || controller.select
            )
        }
    }
}
