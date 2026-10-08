import Foundation

/// Resolves the exact ROM bytes that should be launched for a Build.
///
/// Imported Builds resolve their immutable source ROM. Patch-derived Builds may rebuild a
/// disposable generated-ROM cache before returning the URL. EmulationSession depends on this
/// port so it never assumes that `Build.imageAssetID` must exist on disk permanently.
public protocol BuildImageResolving: Sendable {
    func resolveImageURL(buildID: UUID) throws -> URL
    /// The image's bytes. A resolver that shares the cache with trimming holds the image until
    /// it's read, so a rebuilt image can't be removed in between.
    func readImage(buildID: UUID) throws -> Data
}

extension BuildImageResolving {
    public func readImage(buildID: UUID) throws -> Data {
        try Data(contentsOf: resolveImageURL(buildID: buildID))
    }
}
