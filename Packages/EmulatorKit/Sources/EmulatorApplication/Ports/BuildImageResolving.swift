import Foundation

/// Resolves the exact ROM bytes that should be launched for a Build.
///
/// Imported Builds resolve their immutable source ROM. Patch-derived Builds may rebuild a
/// disposable generated-ROM cache before returning the URL. EmulationSession depends on this
/// port so it never assumes that `Build.imageAssetID` must exist on disk permanently.
public protocol BuildImageResolving: Sendable {
    func resolveImageURL(buildID: UUID) throws -> URL
}
