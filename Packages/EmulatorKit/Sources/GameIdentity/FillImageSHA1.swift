import EmulatorApplication
import EmulatorDomain
import Foundation

/// Computes the SHA-1 of every imported Build that doesn't have one yet, from its source file, so
/// matching against No-Intro's data never has to read ROMs. Imports record it themselves; this
/// covers Builds imported before it was kept, and runs at launch until none are left.
public struct FillImageSHA1: Sendable {
    private let builds: any BuildRepository
    private let assetStore: any AssetStore

    public init(builds: any BuildRepository, assetStore: any AssetStore) {
        self.builds = builds
        self.assetStore = assetStore
    }

    /// Returns how many Builds it filled. A Build whose source file is missing or unreadable is
    /// left for the library check to report, and tried again next time.
    @discardableResult
    public func execute() throws -> Int {
        var filled = 0
        for build in try builds.fetchImportedBuildsMissingImageSHA1() {
            guard let url = try? assetStore.sourceImageURL(sha256: build.imageSHA256),
                  assetStore.fileExists(at: url),
                  let sha1 = try? SHA1Digest.file(at: url) else { continue }
            try builds.setImageSHA1(buildID: build.id, sha1: sha1)
            filled += 1
        }
        return filled
    }
}
