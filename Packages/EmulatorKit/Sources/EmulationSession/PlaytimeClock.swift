import EmulationCore
import Foundation

/// Counts real play time from the frames a session runs. At normal speed a frame counts the time it
/// emulates. Faster, it counts the real time since the frame before, up to the time it emulates, so
/// Fast Forward adds only the time the player spent and a pause between frames adds nothing.
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
        nanoseconds &+= min(now &- lastFrameAt, emulated)
    }

    /// Starts a new session's count at the speed already set.
    public mutating func reset() {
        nanoseconds = 0
        lastFrameAt = nil
    }
}
