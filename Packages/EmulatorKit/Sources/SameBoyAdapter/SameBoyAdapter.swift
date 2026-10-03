import EmulationCore
import EmulatorDomain
import Foundation
import SameBoyBridge

public enum SameBoyAdapterError: Error, Equatable {
    case unsupportedSystem(GameSystem)
    case instanceCreationFailed
    case bootROMUnavailable(String)
    case bootROMLoadFailed
    case romLoadFailed
    case romNotLoaded
    case batterySaveFailed
    case stateSaveFailed
    case stateLoadFailed
}

public final class SameBoyAdapter: EmulatorCore, RumbleCapability, BootSkippingCapability {
    public let descriptor = CoreDescriptor(identifier: "sameboy", version: "1.0.3")
    public let supportedSystems: Set<GameSystem> = [.gameBoy, .gameBoyColor]
    public let stateSerializationVersion = "sameboy-bess-v1"

    private var instance: OpaquePointer?
    private var loadedSystem: GameSystem?

    public init() {}

    deinit {
        if let instance {
            SBDestroy(instance)
        }
    }

    public func loadImage(_ rom: Data, system: GameSystem) throws {
        guard supportedSystems.contains(system) else {
            throw SameBoyAdapterError.unsupportedSystem(system)
        }

        if let instance {
            SBDestroy(instance)
            self.instance = nil
        }

        let model: SBModel = system == .gameBoyColor ? SB_MODEL_CGB : SB_MODEL_DMG
        guard let created = SBCreate(model) else {
            throw SameBoyAdapterError.instanceCreationFailed
        }
        instance = created

        do {
            let bootROM = try Self.loadBootROM(for: system)
            let bootLoaded = bootROM.withUnsafeBytes { bytes in
                SBLoadBootROM(created, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
            }
            guard bootLoaded else { throw SameBoyAdapterError.bootROMLoadFailed }

            let romLoaded = rom.withUnsafeBytes { bytes in
                SBLoadROM(created, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
            }
            guard romLoaded else { throw SameBoyAdapterError.romLoadFailed }
            loadedSystem = system
        } catch {
            SBDestroy(created)
            instance = nil
            throw error
        }
    }

    public func loadPersistentSave(_ data: Data?) throws {
        guard let instance else { throw SameBoyAdapterError.romNotLoaded }
        guard let data, !data.isEmpty else { return }
        data.withUnsafeBytes { bytes in
            SBLoadBattery(instance, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
    }

    public func persistentSaveData() throws -> Data {
        guard let instance else { throw SameBoyAdapterError.romNotLoaded }
        let size = Int(SBBatterySize(instance))
        guard size > 0 else { return Data() }
        var data = Data(count: size)
        let saved = data.withUnsafeMutableBytes { bytes in
            SBSaveBattery(instance, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        guard saved else { throw SameBoyAdapterError.batterySaveFailed }
        return data
    }

    public func runFrame(input: EmulatorInputState) throws -> EmulatorVideoFrame {
        guard let instance else { throw SameBoyAdapterError.romNotLoaded }
        var bridgeInput = SBInputState()
        bridgeInput.up = input.up
        bridgeInput.down = input.down
        bridgeInput.left = input.left
        bridgeInput.right = input.right
        bridgeInput.a = input.a
        bridgeInput.b = input.b
        bridgeInput.start = input.start
        bridgeInput.select = input.select
        SBSetInput(instance, bridgeInput)

        let frame = SBRunFrame(instance)
        guard let pixels = frame.pixels else { throw SameBoyAdapterError.romNotLoaded }
        let byteCount = Int(frame.width) * Int(frame.height) * MemoryLayout<UInt32>.size
        return EmulatorVideoFrame(
            width: Int(frame.width),
            height: Int(frame.height),
            bgra8888: Data(bytes: pixels, count: byteCount),
            emulatedNanoseconds: frame.emulated_nanoseconds
        )
    }

    public func drainAudio(maxFrames: Int) -> [StereoSample] {
        guard let instance, maxFrames > 0 else { return [] }
        var samples = [SBStereoSample](repeating: SBStereoSample(left: 0, right: 0), count: maxFrames)
        let count = samples.withUnsafeMutableBufferPointer { buffer in
            SBDrainAudio(instance, buffer.baseAddress, buffer.count)
        }
        return samples.prefix(Int(count)).map { StereoSample(left: $0.left, right: $0.right) }
    }

    /// The bridge always runs the core unthrottled and reports each frame's emulated time; the
    /// gameplay driver applies the speed by pacing frames, so there is nothing to set here.
    public func setSpeed(_ speed: EmulationSpeed) {}

    public func reset() throws {
        guard let instance else { throw SameBoyAdapterError.romNotLoaded }
        SBReset(instance)
    }

    public func serializeState() throws -> Data {
        guard let instance else { throw SameBoyAdapterError.romNotLoaded }
        let size = Int(SBStateSize(instance))
        guard size > 0 else { throw SameBoyAdapterError.stateSaveFailed }
        var data = Data(count: size)
        let saved = data.withUnsafeMutableBytes { bytes in
            SBSaveState(instance, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        guard saved else { throw SameBoyAdapterError.stateSaveFailed }
        return data
    }

    public func deserializeState(_ data: Data) throws {
        guard let instance else { throw SameBoyAdapterError.romNotLoaded }
        let loaded = data.withUnsafeBytes { bytes in
            SBLoadState(instance, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        guard loaded else { throw SameBoyAdapterError.stateLoadFailed }
    }

    @discardableResult
    public func skipBootAnimation() throws -> Bool {
        guard let instance else { throw SameBoyAdapterError.romNotLoaded }
        // The CGB boot ROM's animation is most of its run time; the fast variant skips it. DMG has no
        // fast variant, and an older resource set without it falls back to the regular boot ROM.
        let fastBootROM = loadedSystem == .gameBoyColor ? Self.bundledBootROM(named: "cgb_boot_fast") : nil
        guard let fastBootROM else { return SBSkipBootROM(instance, nil, 0) }
        return fastBootROM.withUnsafeBytes { bytes in
            SBSkipBootROM(instance, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
    }

    public func consumeRumbleAmplitude() -> Double {
        guard let instance else { return 0 }
        return SBConsumeRumbleAmplitude(instance)
    }

    private static func loadBootROM(for system: GameSystem) throws -> Data {
        let resourceName: String
        switch system {
        case .gameBoy:
            resourceName = "dmg_boot"
        case .gameBoyColor:
            resourceName = "cgb_boot"
        }
        guard let data = bundledBootROM(named: resourceName) else {
            throw SameBoyAdapterError.bootROMUnavailable("\(resourceName).bin")
        }
        return data
    }

    /// SwiftPM's `.process` rule flattens `Resources/BootROMs/` into the bundle root, so look there
    /// first; the subdirectory covers a bundle that keeps the folder.
    private static func bundledBootROM(named resourceName: String) -> Data? {
        let url = Bundle.module.url(forResource: resourceName, withExtension: "bin")
            ?? Bundle.module.url(forResource: resourceName, withExtension: "bin", subdirectory: "BootROMs")
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }
}
