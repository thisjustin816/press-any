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

/// A core that can start a freshly loaded image past its boot animation.
public protocol BootSkippingCapability: AnyObject {
    /// Runs the boot sequence to its hand-off without presenting it. Returns false if the boot
    /// sequence did not finish, in which case the game continues from wherever it stopped.
    @discardableResult
    func skipBootAnimation() throws -> Bool
}

public protocol EmulatorCoreFactory: Sendable {
    var descriptor: CoreDescriptor { get }
    var supportedSystems: Set<GameSystem> { get }
    func makeCore() throws -> any EmulatorCore
}
