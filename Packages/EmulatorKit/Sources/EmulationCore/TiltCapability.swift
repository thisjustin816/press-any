import Foundation

/// Cartridges that read the console's tilt, such as MBC7 games like Kirby Tilt 'n' Tumble.
public protocol TiltCapability: AnyObject {
    /// Whether the loaded cartridge has a tilt sensor.
    var hasTiltSensor: Bool { get }
    /// Tilt in g, within about ±4: `x` toward the screen's right edge going down, `y` toward its
    /// top edge going down, as the cartridge's sensor reads them. Call between frames, on the same
    /// serialized worker as other core operations.
    func setTilt(x: Double, y: Double)
}
