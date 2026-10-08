import EmulationCore
import Foundation

/// A button script a screenshot scene plays from the game's first frame, so a gameplay shot can
/// show the game being played rather than its intro. Set with `-ScreenshotInput "<script>"`, which
/// only Debug builds read.
///
/// The script is whitespace-separated tokens. A number waits that many seconds with nothing held.
/// A button (`a`, `b`, `start`, `select`, `up`, `down`, `left` or `right`) taps it, and
/// `button:seconds` holds it. Buttons joined with `+`, as in `right+a:0.5`, are pressed together.
/// After each press every button is let go for a few frames, so the next press counts as a new one.
///
/// Seconds are the game's own, counted in frames: a slow simulator plays the script exactly as a
/// fast one does, and the same frames reach the game in every scene.
struct ScreenshotInput: Equatable {
    struct ParseError: Error, Equatable, CustomStringConvertible {
        let token: String

        var description: String {
            "\"\(token)\" isn't a number of seconds, a button, or button:seconds"
        }
    }

    /// The Game Boy's frame rate: 70,224 clock ticks a frame at 4,194,304 Hz.
    static let framesPerSecond = 4_194_304.0 / 70_224.0
    static let tapFrames = 6
    static let releaseFrames = 6

    /// The buttons held on each frame, from the first.
    let frames: [EmulatorInputState]

    init(_ script: String) throws {
        var frames: [EmulatorInputState] = []
        for token in script.split(whereSeparator: \.isWhitespace).map(String.init) {
            if let seconds = Self.seconds(token) {
                frames += Array(repeating: EmulatorInputState(), count: Self.frameCount(seconds))
                continue
            }
            let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let buttons = Self.buttons(parts[0]) else { throw ParseError(token: token) }
            var held = Self.tapFrames
            if parts.count == 2 {
                guard let seconds = Self.seconds(parts[1]) else { throw ParseError(token: token) }
                held = max(1, Self.frameCount(seconds))
            }
            frames += Array(repeating: buttons, count: held)
            frames += Array(repeating: EmulatorInputState(), count: Self.releaseFrames)
        }
        self.frames = frames
    }

    private static func seconds(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func frameCount(_ seconds: Double) -> Int {
        Int((seconds * framesPerSecond).rounded())
    }

    private static func buttons(_ text: String) -> EmulatorInputState? {
        var state = EmulatorInputState()
        for name in text.lowercased().split(separator: "+", omittingEmptySubsequences: false) {
            switch name {
            case "a": state.a = true
            case "b": state.b = true
            case "start": state.start = true
            case "select": state.select = true
            case "up": state.up = true
            case "down": state.down = true
            case "left": state.left = true
            case "right": state.right = true
            default: return nil
            }
        }
        return state
    }
}

/// Plays a script one frame at a time. Only the frame loop's queue calls `advance()`.
final class ScreenshotInputPlayer: @unchecked Sendable {
    private let frames: [EmulatorInputState]
    private var next = 0
    private let onFinished: @Sendable () -> Void

    init(_ input: ScreenshotInput, onFinished: @escaping @Sendable () -> Void) {
        frames = input.frames
        self.onFinished = onFinished
    }

    /// The buttons for the frame about to run. Once the script is over it holds nothing, and the
    /// first frame after it calls `onFinished`.
    func advance() -> EmulatorInputState {
        defer { next += 1 }
        if next < frames.count { return frames[next] }
        if next == frames.count { onFinished() }
        return EmulatorInputState()
    }
}
