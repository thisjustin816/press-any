import Foundation
import QuartzCore

/// The refresh rates the display link may ask for while the game is shown. The game always runs
/// at its own 59.73 Hz; this only decides how often a frame can reach the screen.
struct PresentationFrameRate: Equatable {
    var minimum: Float
    var maximum: Float
    var preferred: Float

    /// Up to 120 Hz on ProMotion screens, where a repeated frame lasts half as long.
    static let full = PresentationFrameRate(minimum: 60, maximum: 120, preferred: 120)
    /// What Low Power Mode and thermal pressure ask for: the game's own rate is already near 60 Hz,
    /// so the extra refreshes only cost battery and heat.
    static let capped = PresentationFrameRate(minimum: 60, maximum: 60, preferred: 60)

    static func policy(lowPowerMode: Bool, thermalState: ProcessInfo.ThermalState) -> PresentationFrameRate {
        if lowPowerMode { return .capped }
        switch thermalState {
        case .serious, .critical: return .capped
        case .nominal, .fair: return .full
        @unknown default: return .full
        }
    }

    static func current(_ info: ProcessInfo = .processInfo) -> PresentationFrameRate {
        policy(lowPowerMode: info.isLowPowerModeEnabled, thermalState: info.thermalState)
    }

    var range: CAFrameRateRange {
        CAFrameRateRange(minimum: minimum, maximum: maximum, preferred: preferred)
    }
}
