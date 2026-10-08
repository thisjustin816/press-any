import EmulatorDomain
import Foundation

public enum AttachVariableMapError: Error, Equatable {
    case buildNotFound(UUID)
    /// Not a GB Studio globals file or a symbol file this app can read.
    case unrecognizedFormat
}

/// Attaches a variable map to one exact Build: GB Studio's globals file or a linker symbol file.
/// The file is kept as an immutable source asset; attaching the same map twice is a no-op.
public struct AttachVariableMap: Sendable {
    private let builds: any BuildRepository
    private let maps: any BuildVariableMapRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let transactions: any LibraryTransactionRunner
    private let inFlight: InFlightFiles?
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        builds: any BuildRepository,
        maps: any BuildVariableMapRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        transactions: any LibraryTransactionRunner,
        inFlight: InFlightFiles? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.builds = builds
        self.maps = maps
        self.assets = assets
        self.assetStore = assetStore
        self.transactions = transactions
        self.inFlight = inFlight
        self.now = now
        self.makeID = makeID
    }

    public func execute(buildID: UUID, sourceURL: URL) throws -> BuildVariableMap {
        guard try builds.fetchBuild(id: buildID) != nil else { throw AttachVariableMapError.buildNotFound(buildID) }
        try ImportSizeLimit.variableMap.check(fileAt: sourceURL)
        let staged = try assetStore.stageCopy(from: sourceURL, transactionID: makeID())
        defer { try? assetStore.removeIfExists(staged.deletingLastPathComponent()) }

        guard let format = Self.format(of: try assetStore.readData(at: staged)) else {
            throw AttachVariableMapError.unrecognizedFormat
        }
        let sha = try assetStore.hashFile(at: staged)
        let fileExtension = sourceURL.pathExtension.isEmpty ? "txt" : sourceURL.pathExtension.lowercased()
        let existingAsset = try assets.fetchSourceAsset(kind: .variableMap, sha256: sha)
        if let existingAsset, let attached = try maps.fetchVariableMaps(buildID: buildID).first(where: { $0.assetID == existingAsset.id }) {
            return attached
        }
        let destination = try assetStore.variableMapURL(sha256: sha, extension: fileExtension)
        // Held until the records are in, so Check Library Files doesn't take the placed file for
        // an orphan.
        let lease = inFlight?.lease()
        defer { lease?.end() }
        lease?.hold(try assetStore.managedRelativePath(for: destination))
        let destinationExisted = assetStore.fileExists(at: destination)
        // Committing checks a stored file against its hash and replaces it if it was damaged.
        let committed = try assetStore.commitVariableMap(stagedURL: staged, sha256: sha, extension: existingAsset.map {
            URL(fileURLWithPath: $0.relativePath).pathExtension
        } ?? fileExtension)

        let timestamp = now()
        let asset = try existingAsset ?? ManagedAsset(
            id: makeID(),
            kind: .variableMap,
            storageClass: .source,
            contentSHA256: sha,
            byteLength: try assetStore.fileByteLength(at: committed),
            relativePath: try assetStore.managedRelativePath(for: committed),
            originalFilename: sourceURL.lastPathComponent,
            integrityStatus: .verified,
            createdAt: timestamp
        )
        let map = BuildVariableMap(
            id: makeID(),
            buildID: buildID,
            assetID: asset.id,
            format: format,
            source: .userImport,
            originalFilename: sourceURL.lastPathComponent,
            attachedAt: timestamp
        )
        do {
            try transactions.run { [assets, maps] in
                if existingAsset == nil { try assets.insertAsset(asset) }
                try maps.insertVariableMap(map)
            }
        } catch {
            if existingAsset == nil, !destinationExisted { try? assetStore.removeIfExists(committed) }
            throw error
        }
        return map
    }

    /// The map's format, or nil when it isn't one. A file qualifies when most of its non-blank,
    /// non-comment lines have one format's shape.
    static func format(of data: Data) -> BuildVariableMap.Format? {
        guard data.count <= ImportSizeLimit.variableMap.bytes, let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(";") && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
        guard !lines.isEmpty else { return nil }
        let shapes: [(BuildVariableMap.Format, String)] = [
            (.gbStudioGlobals, #"^[A-Za-z_][A-Za-z0-9_]*\s*(=|EQU)\s*(\$|0x)?[0-9A-Fa-f]+$"#),
            (.symbolFile, #"^([0-9A-Fa-f]{2}:[0-9A-Fa-f]{4}\s+\S+|DEF\s+\S+\s+0x[0-9A-Fa-f]+)$"#),
        ]
        for (format, pattern) in shapes {
            let matching = lines.filter { $0.range(of: pattern, options: .regularExpression) != nil }.count
            if matching * 2 > lines.count { return format }
        }
        return nil
    }
}
