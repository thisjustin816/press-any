import Foundation

public protocol PatchApplying: Sendable {
    func apply(patch: Data, fileExtension: String, to source: Data) throws -> Data
}
