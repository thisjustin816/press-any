import CoreMotion
import Foundation
import UIKit

/// The phone's tilt for cartridges that sense it, measured from how the player held the phone when
/// play started or they last chose Recenter Tilt. Motion updates arrive on their own queue; the
/// frame loop reads the latest before each frame.
final class GameplayTilt: @unchecked Sendable {
    /// Tilt beyond this many g reads as this much, well inside what the cartridge can sense.
    static let limit = 2.0

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var current = (x: 0.0, y: 0.0)
    private var baseline: (x: Double, y: Double)?
    private var orientation = UIInterfaceOrientation.portrait
    private var active = false

    init() {
        queue.name = "Gameplay.Tilt"
        queue.maxConcurrentOperationCount = 1
    }

    /// The latest tilt, in g, as the cartridge reads it.
    var value: (x: Double, y: Double) { lock.withLock { current } }

    /// Runs the motion sensor only while the game runs.
    func setActive(_ active: Bool) {
        let changed = lock.withLock { () -> Bool in
            defer { self.active = active }
            return self.active != active
        }
        guard changed, manager.isDeviceMotionAvailable else { return }
        if active {
            manager.deviceMotionUpdateInterval = 1.0 / 60.0
            manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
                guard let self, let gravity = motion?.gravity else { return }
                self.update(gravityX: gravity.x, gravityY: gravity.y)
            }
        } else {
            manager.stopDeviceMotionUpdates()
        }
    }

    /// A turned screen turns the axes, so the phone's position then becomes level again.
    func setOrientation(_ orientation: UIInterfaceOrientation) {
        lock.withLock {
            guard self.orientation != orientation else { return }
            self.orientation = orientation
            baseline = nil
            current = (0, 0)
        }
    }

    /// The way the phone is held now becomes level.
    func recenter() {
        lock.withLock {
            baseline = nil
            current = (0, 0)
        }
    }

    private func update(gravityX: Double, gravityY: Double) {
        lock.withLock {
            let raw = Self.reading(gravityX: gravityX, gravityY: gravityY, orientation: orientation)
            let base = baseline ?? raw
            baseline = base
            current = (Self.clamp(raw.x - base.x), Self.clamp(raw.y - base.y))
        }
    }

    /// Gravity in the phone's own axes, turned to the screen as the interface is shown, as the
    /// cartridge reads it: `x` is gravity toward the screen's left edge and `y` toward its top.
    static func reading(gravityX: Double, gravityY: Double, orientation: UIInterfaceOrientation) -> (x: Double, y: Double) {
        let screen: (right: Double, up: Double)
        switch orientation {
        case .portraitUpsideDown: screen = (-gravityX, -gravityY)
        case .landscapeRight: screen = (-gravityY, gravityX)
        case .landscapeLeft: screen = (gravityY, -gravityX)
        default: screen = (gravityX, gravityY)
        }
        return (-screen.right, screen.up)
    }

    private static func clamp(_ value: Double) -> Double { min(limit, max(-limit, value)) }
}
