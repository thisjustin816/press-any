import EmulationCore
import Foundation

/// Counts real play time from the frames a session runs. At normal speed a frame counts the time it
/// emulates. At any other speed it counts the real time since the frame before, up to how long the
/// frame lasts at that speed, so Fast Forward and slow motion add only the time the player spent
/// and a pause between frames adds nothing. Rewind, when it comes, should count the same way.
public struct PlaytimeClock: Sendable {
    public private(set) var nanoseconds: UInt64 = 0
    private var speed = EmulationSpeed.normal
    private var lastFrameAt: UInt64?
    private let uptime: @Sendable () -> UInt64

    public init(uptime: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.uptime = uptime
    }

    public mutating func setSpeed(_ speed: EmulationSpeed) {
        self.speed = speed
    }

    public mutating func ranFrame(lasting emulated: UInt64) {
        let now = uptime()
        defer { lastFrameAt = now }
        guard speed != .normal, let lastFrameAt else {
            nanoseconds &+= emulated
            return
        }
        nanoseconds &+= min(now &- lastFrameAt, realLength(of: emulated))
    }

    /// The real time a frame takes at the current speed; one frame's game time when faster.
    private func realLength(of emulated: UInt64) -> UInt64 {
        guard case .multiplier(let value) = speed, value > 0, value < 1 else { return emulated }
        return UInt64(Double(emulated) / value)
    }

    /// Starts a new session's count at the speed already set.
    public mutating func reset() {
        nanoseconds = 0
        lastFrameAt = nil
    }
}
