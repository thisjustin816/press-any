import EmulatorDomain
import Foundation

public protocol EmulatorCore: AnyObject {
    var descriptor: CoreDescriptor { get }
    var supportedSystems: Set<GameSystem> { get }
    var stateSerializationVersion: String { get }

    func loadImage(_ rom: Data, system: GameSystem) throws
    func loadPersistentSave(_ data: Data?) throws
    func persistentSaveData() throws -> Data

    func runFrame(input: EmulatorInputState) throws -> EmulatorVideoFrame
    func drainAudio(maxFrames: Int) -> [StereoSample]

    func setSpeed(_ speed: EmulationSpeed)
    func reset() throws

    func serializeState() throws -> Data
    func deserializeState(_ data: Data) throws
}

public protocol RumbleCapability: AnyObject {
    func consumeRumbleAmplitude() -> Double
}

public protocol DisplaySettingsCapability: AnyObject {
    /// Applies the display settings and returns a refreshed picture without advancing gameplay.
    /// Before the first frame, there is no picture to refresh.
    func setDisplaySettings(colorCorrection: ColorCorrection, dmgPalette: DMGPalette) throws -> EmulatorVideoFrame?
}

/// A core that can start a freshly loaded image past its boot animation.
public protocol BootSkippingCapability: AnyObject {
    /// Runs the boot sequence to its hand-off without presenting it. Returns false if the boot
    /// sequence did not finish, in which case the game continues from wherever it stopped.
    @discardableResult
    func skipBootAnimation() throws -> Bool
}

/// A core that can run a game on hardware other than its system's own.
public protocol HardwareModelCapability: AnyObject {
    /// The model the next image loads on, and with an image loaded, the model it switches to: the
    /// game starts again from its boot on the new hardware, keeping its battery save, cheats and
    /// display settings. If the switch fails, the game keeps running as it was.
    func setHardwareModel(_ model: HardwareModel) throws
}

/// A save state made on hardware of another family than the game runs on, which won't load until
/// the game runs on that family again.
public struct StateNeedsOtherHardware: Error, Equatable, LocalizedError {
    public let family: HardwareFamily

    public init(family: HardwareFamily) {
        self.family = family
    }

    public var errorDescription: String? {
        let names = family.models.map(\.displayName)
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " or " + names.last! : names[0]
        return "It was made on a \(list). Set Model to \(names.count > 1 ? "one of those" : "that") to load it."
    }
}

public protocol EmulatorCoreFactory: Sendable {
    var descriptor: CoreDescriptor { get }
    var supportedSystems: Set<GameSystem> { get }
    func makeCore() throws -> any EmulatorCore
}
