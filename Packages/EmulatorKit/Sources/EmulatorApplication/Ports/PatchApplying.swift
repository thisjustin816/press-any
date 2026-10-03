import Foundation

public protocol PatchApplying: Sendable {
    /// `ignoringBaseMismatch` is the user's explicit Apply Anyway: a patch whose format records
    /// its expected base is applied to a different one. The patch's own integrity is still checked.
    func apply(patch: Data, fileExtension: String, to source: Data, ignoringBaseMismatch: Bool) throws -> Data
}

extension PatchApplying {
    public func apply(patch: Data, fileExtension: String, to source: Data) throws -> Data {
        try apply(patch: patch, fileExtension: fileExtension, to: source, ignoringBaseMismatch: false)
    }
}
