import EmulationCore
import EmulatorDomain
import Foundation

/// Keeps prints in their Game's Captures. A print is saved as soon as paper comes out, and saved
/// again under the same ID when the game feeds more paper onto it. Each new print may push the
/// Game's oldest unpinned print past `Capture.keepCount` into Recently Deleted.
public struct PrintCaptures: Sendable {
    private let captures: any CaptureRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let transactions: any LibraryTransactionRunner
    private let deletion: LibraryDeletionOperations
    private let now: @Sendable () -> Date

    public init(
        captures: any CaptureRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        transactions: any LibraryTransactionRunner,
        deletion: LibraryDeletionOperations,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.captures = captures
        self.assets = assets
        self.assetStore = assetStore
        self.transactions = transactions
        self.deletion = deletion
        self.now = now
    }

    /// Saves the slip, or its longer paper when it is already saved. Returns nil when the print
    /// was deleted while the game was still feeding it, since nothing is brought back.
    /// `printedAt` dates a print made elsewhere, such as in Quick Play; it defaults to now.
    @discardableResult
    public func save(
        _ slip: PrinterSlip, gameID: UUID, buildID: UUID?, saveProfileID: UUID?, printedAt: Date? = nil
    ) throws -> Capture? {
        let data = try PrinterSlipArchive.encode(slip)
        let url = assetStore.captureURL(captureID: slip.id)
        let relativePath = try assetStore.managedRelativePath(for: url)
        let timestamp = now()
        if var existing = try captures.fetchCapture(id: slip.id) {
            guard let asset = try assets.fetchAsset(id: existing.assetID) else { return nil }
            try assetStore.writeDataAtomically(data, to: url)
            existing.modifiedAt = timestamp
            let capture = existing
            try transactions.run { [assets, captures, assetStore] in
                try assets.updateMutableAsset(ManagedAsset(
                    id: asset.id, kind: asset.kind, storageClass: asset.storageClass,
                    contentSHA256: assetStore.hashData(data), byteLength: Int64(data.count),
                    relativePath: asset.relativePath, integrityStatus: .verified, createdAt: asset.createdAt
                ))
                try captures.updateCapture(capture)
            }
            return capture
        }
        // A capture's file is named for it, so its asset outliving the live row means the print
        // is in Recently Deleted.
        guard try assets.fetchAsset(relativePath: relativePath) == nil else { return nil }
        try assetStore.writeDataAtomically(data, to: url)
        let asset = ManagedAsset(
            id: UUID(), kind: .capture, storageClass: .userData,
            contentSHA256: assetStore.hashData(data), byteLength: Int64(data.count),
            relativePath: relativePath, integrityStatus: .verified, createdAt: timestamp
        )
        let capture = Capture(
            id: slip.id, gameID: gameID, buildID: buildID, saveProfileID: saveProfileID, kind: .print,
            assetID: asset.id, createdAt: printedAt ?? timestamp, modifiedAt: timestamp
        )
        do {
            try transactions.run { [assets, captures] in
                try assets.insertAsset(asset)
                try captures.insertCapture(capture)
            }
        } catch {
            try? assetStore.removeIfExists(url)
            throw error
        }
        try deletion.cleanCaptures(gameID: gameID)
        return capture
    }

    /// Newest first.
    public func captures(gameID: UUID) throws -> [Capture] {
        try captures.fetchCaptures(gameID: gameID)
    }

    public func slip(for capture: Capture) throws -> PrinterSlip {
        guard let asset = try assets.fetchAsset(id: capture.assetID) else { throw LibraryDeletionError.captureNotFound(capture.id) }
        let data = try assetStore.readData(at: try assetStore.managedURL(relativePath: asset.relativePath))
        return try PrinterSlipArchive.decode(data, id: capture.id)
    }

    /// Moves a print to Recently Deleted. One that was never saved has nothing to move. Paper the
    /// game feeds onto it afterward isn't saved, as for any deleted print.
    public func delete(captureID: UUID) throws {
        guard try captures.fetchCapture(id: captureID) != nil else { return }
        try deletion.delete(deletion.planCaptureDeletion(captureIDs: [captureID]))
    }

    /// A pinned print never counts toward the cap. Unpinning one can push the oldest past it.
    public func setPinned(_ isPinned: Bool, captureID: UUID) throws {
        guard var capture = try captures.fetchCapture(id: captureID) else { throw LibraryDeletionError.captureNotFound(captureID) }
        guard capture.isPinned != isPinned else { return }
        capture.isPinned = isPinned
        try captures.updateCapture(capture)
        if !isPinned { try deletion.cleanCaptures(gameID: capture.gameID) }
    }
}
