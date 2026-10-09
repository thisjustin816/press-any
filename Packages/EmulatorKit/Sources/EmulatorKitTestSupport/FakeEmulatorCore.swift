import EmulationCore
import EmulatorDomain
import Foundation

// Test doubles for the core boundary. This target is never linked into the app.

public enum FakeEmulatorCoreError: Error {
    case unsupportedSystem(GameSystem)
    case romNotLoaded
    case stateLoadFailedPartway
    case cheatCodeRefused
}

public struct FakeCoreFactory: EmulatorCoreFactory {
    public let descriptor: CoreDescriptor
    public let supportedSystems: Set<GameSystem>

    public init(
        descriptor: CoreDescriptor,
        supportedSystems: Set<GameSystem> = [.gameBoy, .gameBoyColor]
    ) {
        self.descriptor = descriptor
        self.supportedSystems = supportedSystems
    }

    public func makeCore() throws -> any EmulatorCore {
        FakeEmulatorCore(descriptor: descriptor, supportedSystems: supportedSystems)
    }
}

public final class FakeEmulatorCore: EmulatorCore, BootSkippingCapability, CheatCapability {
    public let descriptor: CoreDescriptor
    public let supportedSystems: Set<GameSystem>
    public let stateSerializationVersion = "fake-json-v1"

    private var loadedSystem: GameSystem?
    private var battery = Data()
    private var frameCounter: UInt64 = 0
    private var pendingAudio = [StereoSample]()
    private var speed: EmulationSpeed = .normal
    public private(set) var bootAnimationSkips = 0
    public private(set) var cheatCodes: [String] = []
    public private(set) var cheatsEnabled = true
    /// The frames run since the image loaded at each change to the codes or their switch.
    public private(set) var framesRunAtCheatChanges: [UInt64] = []
    /// Makes the next state load write the state's cartridge RAM and then fail, as SameBoy does
    /// with a state that ends early.
    public var failsNextStateLoadPartway = false

    public init(
        descriptor: CoreDescriptor = .init(identifier: "fake", version: "1.0.0"),
        supportedSystems: Set<GameSystem> = [.gameBoy, .gameBoyColor]
    ) {
        self.descriptor = descriptor
        self.supportedSystems = supportedSystems
    }

    public func loadImage(_ rom: Data, system: GameSystem) throws {
        guard supportedSystems.contains(system) else {
            throw FakeEmulatorCoreError.unsupportedSystem(system)
        }
        loadedSystem = system
        frameCounter = 0
        pendingAudio.removeAll(keepingCapacity: true)
        _ = rom
    }

    public func loadPersistentSave(_ data: Data?) throws {
        battery = data ?? Data()
    }

    public func persistentSaveData() throws -> Data {
        battery
    }

    /// Stands in for the game writing its cartridge RAM.
    public func writeBattery(_ data: Data) {
        battery = data
    }

    public func runFrame(input: EmulatorInputState) throws -> EmulatorVideoFrame {
        guard loadedSystem != nil else { throw FakeEmulatorCoreError.romNotLoaded }
        frameCounter &+= 1

        let width = 160
        let height = 144
        var pixels = Data(repeating: 0, count: width * height * 4)
        pixels[0] = UInt8(truncatingIfNeeded: frameCounter)
        pixels[1] = input.a ? 0xff : 0
        pixels[2] = input.b ? 0xff : 0
        pixels[3] = 0xff

        let sampleValue = Int16(truncatingIfNeeded: frameCounter)
        pendingAudio.append(StereoSample(left: sampleValue, right: -sampleValue))

        return EmulatorVideoFrame(
            width: width,
            height: height,
            bgra8888: pixels,
            emulatedNanoseconds: 16_742_706
        )
    }

    public func drainAudio(maxFrames: Int) -> [StereoSample] {
        guard maxFrames > 0, !pendingAudio.isEmpty else { return [] }
        let count = min(maxFrames, pendingAudio.count)
        let drained = Array(pendingAudio.prefix(count))
        pendingAudio.removeFirst(count)
        return drained
    }

    public func setSpeed(_ speed: EmulationSpeed) {
        self.speed = speed
    }

    public func reset() throws {
        guard loadedSystem != nil else { throw FakeEmulatorCoreError.romNotLoaded }
        frameCounter = 0
        pendingAudio.removeAll(keepingCapacity: true)
    }

    public func serializeState() throws -> Data {
        // JSONEncoder doesn't promise a key order, so two encodes of one state could differ.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(
            SerializedState(frameCounter: frameCounter, battery: battery, system: loadedSystem)
        )
    }

    public func deserializeState(_ data: Data) throws {
        let state = try JSONDecoder().decode(SerializedState.self, from: data)
        if failsNextStateLoadPartway {
            failsNextStateLoadPartway = false
            battery = state.battery
            throw FakeEmulatorCoreError.stateLoadFailedPartway
        }
        frameCounter = state.frameCounter
        battery = state.battery
        loadedSystem = state.system
        pendingAudio.removeAll(keepingCapacity: true)
    }

    public func setCheatCodes(_ codes: [String]) throws {
        guard codes.allSatisfy(isValidCheatCode) else { throw FakeEmulatorCoreError.cheatCodeRefused }
        cheatCodes = codes
        framesRunAtCheatChanges.append(frameCounter)
    }

    public func setCheatsEnabled(_ enabled: Bool) {
        cheatsEnabled = enabled
        framesRunAtCheatChanges.append(frameCounter)
    }

    /// Reads any code of hex digits and dashes.
    public func isValidCheatCode(_ code: String) -> Bool {
        !code.isEmpty && code.allSatisfy { $0.isHexDigit || $0 == "-" }
    }

    @discardableResult
    public func skipBootAnimation() throws -> Bool {
        guard loadedSystem != nil else { throw FakeEmulatorCoreError.romNotLoaded }
        bootAnimationSkips += 1
        return true
    }

    public var configuredSpeed: EmulationSpeed {
        speed
    }
}

private struct SerializedState: Codable {
    let frameCounter: UInt64
    let battery: Data
    let system: GameSystem?
}
