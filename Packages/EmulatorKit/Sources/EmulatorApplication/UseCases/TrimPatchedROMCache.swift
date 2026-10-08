import EmulatorDomain
import Foundation

/// Removes patched ROMs from the cache, least recently played first, while the device is short
/// of space. It follows Clear Patched ROM Cache's rules, keeps any file an operation holds, such as
/// the running game's image, and stops once enough space is back.
public struct TrimPatchedROMCache: Sendable {
    /// The free space for important use that trimming restores. Patched ROMs are 8 MB at most, so
    /// trimming only helps a nearly full device, and this keeps room for saves and states to write.
    public static let minimumFreeBytes: Int64 = 500_000_000

    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let states: any SaveStateRepository
    private let cache: GeneratedImageCache
    private let minimumFreeBytes: Int64
    private let freeBytes: @Sendable () throws -> Int64?

    /// `freeBytes` reads the device's free space for important use, or nil when it's unknown,
    /// which leaves the cache as it is.
    public init(
        assets: any ManagedAssetInventoryRepository,
        builds: any BuildRepository,
        recipes: any PatchRecipeRepository,
        profiles: any SaveProfileRepository,
        states: any SaveStateRepository,
        assetStore: any AssetStore,
        inFlight: InFlightFiles? = nil,
        minimumFreeBytes: Int64 = Self.minimumFreeBytes,
        freeBytes: @escaping @Sendable () throws -> Int64?
    ) {
        self.builds = builds
        self.profiles = profiles
        self.states = states
        cache = GeneratedImageCache(assets: assets, builds: builds, recipes: recipes, assetStore: assetStore,
            inFlight: inFlight)
        self.minimumFreeBytes = minimumFreeBytes
        self.freeBytes = freeBytes
    }

    /// `incomingBytes` is the size of an image about to be written, which needs room too.
    /// Returns the relative paths removed, in the order they went.
    @discardableResult
    public func execute(incomingBytes: Int64 = 0) throws -> [String] {
        guard let free = try freeBytes() else { return [] }
        var shortfall = minimumFreeBytes + incomingBytes - free
        guard shortfall > 0 else { return [] }

        let lastUse = try lastUseDates()
        // An image nobody has played since it was made goes by when it was made, so a new
        // patched Build isn't the first to go.
        let candidates = try cache.removableImages().map { asset in
            (asset, max(asset.createdAt, lastUse[asset.contentSHA256] ?? .distantPast))
        }.sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.relativePath < rhs.0.relativePath
        }
        var removed: [String] = []
        for (asset, _) in candidates where shortfall > 0 {
            guard try cache.remove(asset) else { continue }
            removed.append(asset.relativePath)
            shortfall -= asset.byteLength
        }
        return removed
    }

    /// When each image was last played, by its SHA-256. Every library session that ends normally
    /// leaves an Auto State, so a Build's newest state marks its last play without a separate
    /// record. Copies of a Build share their image, so the image goes by the latest of them.
    private func lastUseDates() throws -> [String: Date] {
        var buildLastUse: [UUID: Date] = [:]
        for profile in try profiles.fetchAllSaveProfiles() {
            for state in try states.fetchSaveStates(saveProfileID: profile.id) {
                buildLastUse[state.buildID] = max(buildLastUse[state.buildID] ?? .distantPast, state.createdAt)
            }
        }
        var imageLastUse: [String: Date] = [:]
        for build in try builds.fetchAllBuilds() {
            guard let date = buildLastUse[build.id] else { continue }
            imageLastUse[build.imageSHA256] = max(imageLastUse[build.imageSHA256] ?? .distantPast, date)
        }
        return imageLastUse
    }
}
