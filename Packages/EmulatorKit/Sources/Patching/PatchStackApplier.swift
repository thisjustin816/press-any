import EmulatorApplication
import Foundation

public struct PatchStackItem: Equatable, Sendable {
    public let data: Data
    public let fileExtension: String
    public let enabled: Bool

    public init(data: Data, fileExtension: String, enabled: Bool = true) {
        self.data = data
        self.fileExtension = fileExtension
        self.enabled = enabled
    }
}

public struct PatchStackApplier: PatchApplying, Sendable {
    public init() {}

    public func apply(
        patch: Data,
        fileExtension: String,
        to source: Data,
        ignoringBaseMismatch: Bool
    ) throws -> Data {
        try ImportSizeLimit.patch.check(byteCount: Int64(patch.count))
        let normalized = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let result: Data
        switch normalized {
        case "ips":
            result = try IPSPatchApplier().apply(patch: patch, to: source)
        case "bps":
            result = try BPSPatchApplier().apply(patch: patch, to: source, ignoringBaseMismatch: ignoringBaseMismatch)
        default:
            throw PatchError.unsupportedFormat(normalized)
        }
        // An IPS patch can address up to 16 MB, more than any cartridge maps or the core loads.
        guard result.count <= ImportSizeLimit.rom.bytes else { throw PatchError.targetTooLarge(result.count) }
        return result
    }

    public func apply(items: [PatchStackItem], to source: Data) throws -> Data {
        try items.reduce(source) { current, item in
            guard item.enabled else { return current }
            return try apply(patch: item.data, fileExtension: item.fileExtension, to: current)
        }
    }
}
