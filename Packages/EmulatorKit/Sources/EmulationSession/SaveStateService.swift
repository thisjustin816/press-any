import EmulatorApplication
import EmulatorDomain
import EmulationCore
import Foundation

public enum SaveStateServiceError: Error, Equatable, LocalizedError {
    case contextMismatch
    case coreMismatch(expected: CoreDescriptor, actual: CoreDescriptor)
    case serializationVersionMismatch(expected: String, actual: String)
    case assetNotFound(UUID)
    case hashMismatch(assetID: UUID, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .hashMismatch:
            return "This save state is damaged, so it wasn't loaded. The file was kept."
        default:
            return nil
        }
    }
}

public struct SaveStateService: Sendable {
    private let states: any SaveStateRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let transactions: any LibraryTransactionRunner
    private let retention: AutoStateRetention
    private let settings: SettingsResolver?
    private let deletion: LibraryDeletionOperations?
    private let thumbnails: (any FrameImageEncoding)?
    /// False keeps only the newest unpinned Auto State, whatever Keep Auto States says. It's read
    /// at each Auto State write, so turning it off deletes nothing until the next one.
    private let keepsAutoStateHistory: @Sendable () -> Bool
    private let now: @Sendable () -> Date

    public init(
        states: any SaveStateRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        retention: AutoStateRetention = .init(),
        settings: SettingsResolver? = nil,
        deletion: LibraryDeletionOperations? = nil,
        transactions: any LibraryTransactionRunner = PassthroughTransactionRunner(),
        thumbnails: (any FrameImageEncoding)? = nil,
        keepsAutoStateHistory: @escaping @Sendable () -> Bool = { true },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.states = states
        self.assets = assets
        self.assetStore = assetStore
        self.retention = retention
        self.settings = settings
        self.deletion = deletion
        self.transactions = transactions
        self.thumbnails = thumbnails
        self.keepsAutoStateHistory = keepsAutoStateHistory
        self.now = now
    }

    @discardableResult
    public func save(
        worker: SessionWorker,
        context: LaunchContext,
        kind: SaveStateKind,
        label: String? = nil,
        slot: Int? = nil,
        isTimed: Bool = false,
        playtimeSeconds: Double,
        frame: EmulatorVideoFrame? = nil
    ) throws -> SaveState {
        if kind == .slot && (slot ?? 0) <= 0 { throw SaveSlotStateError.invalidSlot }
        let payload = try worker.perform { try $0.serializeState() }
        let core = try worker.perform { $0.descriptor }
        let serializationVersion = try worker.perform { $0.stateSerializationVersion }
        let stateID = UUID()
        let assetID = UUID()
        let destination = assetStore.stateURL(stateID: stateID)
        try assetStore.writeDataAtomically(payload, to: destination)

        let timestamp = now()
        let asset = ManagedAsset(
            id: assetID,
            kind: .saveState,
            storageClass: .userData,
            contentSHA256: assetStore.hashData(payload),
            byteLength: Int64(payload.count),
            relativePath: try assetStore.managedRelativePath(for: destination),
            integrityStatus: .verified,
            createdAt: timestamp
        )

        // A thumbnail is a convenience: one that can't be made leaves the state without it.
        let thumbnail = (kind == .crashRecovery ? nil : frame).flatMap { try? saveThumbnail($0, stateID: stateID, timestamp: timestamp) }

        let state: SaveState
        do {
            try assets.insertAsset(asset)
            do {
                let autoSequence: Int?
                if kind == .auto {
                    let existing = try states.fetchSaveStates(
                        buildID: context.buildID,
                        saveProfileID: context.saveProfileID
                    )
                    autoSequence = (existing.compactMap(\.autoSequence).max() ?? 0) + 1
                } else {
                    autoSequence = nil
                }
                let candidate = SaveState(
                    id: stateID,
                    buildID: context.buildID,
                    saveProfileID: context.saveProfileID,
                    core: core,
                    stateSerializationVersion: serializationVersion,
                    stateAssetID: assetID,
                    screenshotAssetID: thumbnail?.id,
                    kind: kind,
                    slot: kind == .slot ? slot : nil,
                    isTimed: isTimed,
                    autoSequence: autoSequence,
                    label: label,
                    playtimeSeconds: playtimeSeconds,
                    createdAt: timestamp
                )
                if kind == .quick {
                    let result = try SaveQuickState(states: states, transactions: transactions).execute(candidate)
                    state = result.saved
                    if let previous = result.previous { discardAssets(of: previous) }
                } else if kind == .slot {
                    let result = try SaveSlotState(states: states, transactions: transactions).execute(candidate)
                    state = result.saved
                    if let previous = result.previous { discardAssets(of: previous) }
                } else {
                    try insertState(candidate, context: context)
                    state = candidate
                }
            } catch {
                try? assets.deleteAsset(id: assetID)
                throw error
            }
        } catch {
            try? assetStore.removeIfExists(destination)
            if let thumbnail { assets.discard(thumbnail, files: assetStore) }
            throw error
        }

        // The new state is complete. Pruning older ones is housekeeping, and a failure there must
        // not take the new state with it; the next save prunes again.
        if kind == .auto {
            try? pruneAutoStates(context: context)
        } else if kind == .manual {
            try? pruneManualStates(context: context, keeping: state.id)
        }
        return state
    }

    private func insertState(_ state: SaveState, context: LaunchContext) throws {
        guard state.kind == .crashRecovery else {
            try states.insertSaveState(state)
            return
        }
        let previous = try states.fetchSaveStates(buildID: context.buildID, saveProfileID: context.saveProfileID)
            .filter { $0.kind == .crashRecovery }
        // Publishing the checkpoint and retiring its predecessor share a database transaction,
        // so an interrupted replacement leaves one complete checkpoint referenced.
        try transactions.run {
            try states.insertSaveState(state)
            for old in previous { try states.deleteSaveState(id: old.id) }
        }
        for old in previous { discardAssets(of: old) }
    }

    private func discardAssets(of state: SaveState) {
        assets.discard(assetID: state.stateAssetID, files: assetStore)
        assets.discard(assetID: state.screenshotAssetID, files: assetStore)
    }

    public func removeCrashRecoveryStates(context: LaunchContext, keeping stateID: UUID? = nil) throws {
        let all = try states.fetchSaveStates(buildID: context.buildID, saveProfileID: context.saveProfileID)
        for state in all where state.kind == .crashRecovery && state.id != stateID {
            let asset = try assets.fetchAsset(id: state.stateAssetID)
            let thumbnail = try state.screenshotAssetID.flatMap { try assets.fetchAsset(id: $0) }
            try states.deleteSaveState(id: state.id)
            if let asset { assets.discard(asset, files: assetStore) }
            if let thumbnail { assets.discard(thumbnail, files: assetStore) }
        }
    }

    /// The state's thumbnail image, or nil when it has none or it can't be read.
    public func thumbnailData(for state: SaveState) -> Data? {
        guard let assetID = state.screenshotAssetID,
              let asset = try? assets.fetchAsset(id: assetID),
              let url = try? assetStore.managedURL(relativePath: asset.relativePath)
        else { return nil }
        return try? assetStore.readData(at: url)
    }

    private func saveThumbnail(_ frame: EmulatorVideoFrame, stateID: UUID, timestamp: Date) throws -> ManagedAsset? {
        guard let thumbnails else { return nil }
        let data = try thumbnails.encode(frame)
        let destination = try assetStore.stateThumbnailURL(stateID: stateID, extension: thumbnails.fileExtension)
        try assetStore.writeDataAtomically(data, to: destination)
        let asset = ManagedAsset(
            id: UUID(),
            kind: .stateThumbnail,
            storageClass: .userData,
            contentSHA256: assetStore.hashData(data),
            byteLength: Int64(data.count),
            relativePath: try assetStore.managedRelativePath(for: destination),
            integrityStatus: .verified,
            createdAt: timestamp
        )
        do {
            try assets.insertAsset(asset)
        } catch {
            try? assetStore.removeIfExists(destination)
            throw error
        }
        return asset
    }

    public func load(
        _ state: SaveState,
        worker: SessionWorker,
        context: LaunchContext
    ) throws {
        guard state.buildID == context.buildID, state.saveProfileID == context.saveProfileID else {
            throw SaveStateServiceError.contextMismatch
        }

        let currentCore = try worker.perform { $0.descriptor }
        guard state.core == currentCore else {
            throw SaveStateServiceError.coreMismatch(expected: state.core, actual: currentCore)
        }

        let currentVersion = try worker.perform { $0.stateSerializationVersion }
        guard state.stateSerializationVersion == currentVersion else {
            throw SaveStateServiceError.serializationVersionMismatch(
                expected: state.stateSerializationVersion,
                actual: currentVersion
            )
        }

        guard var asset = try assets.fetchAsset(id: state.stateAssetID) else {
            throw SaveStateServiceError.assetNotFound(state.stateAssetID)
        }
        let url = try assetStore.managedURL(relativePath: asset.relativePath)
        let payload = try assetStore.readData(at: url)
        let actual = assetStore.hashData(payload)
        guard actual == asset.contentSHA256 else {
            if asset.integrityStatus != .corrupt {
                asset.integrityStatus = .corrupt
                try? assets.updateMutableAsset(asset)
            }
            throw SaveStateServiceError.hashMismatch(assetID: asset.id, expected: asset.contentSHA256, actual: actual)
        }
        try worker.perform { try $0.deserializeState(payload) }
    }

    private func pruneManualStates(context: LaunchContext, keeping stateID: UUID) throws {
        let keep = try settings?.appValue(KeepSaveStates.self, key: .keepSaveStates) ?? .all
        if let count = keep.keepCount { try deletion?.cleanManualStates(context: context, keepCount: count, keeping: stateID) }
    }

    private func pruneAutoStates(context: LaunchContext) throws {
        let all = try states.fetchSaveStates(buildID: context.buildID, saveProfileID: context.saveProfileID)
        let policy: AutoStateRetention
        if keepsAutoStateHistory() {
            let configured = try settings?.appValue(KeepAutoStates.self, key: .keepAutoStates)
            policy = configured.map { AutoStateRetention(keepCount: $0.rawValue) } ?? retention
        } else {
            policy = AutoStateRetention(keepCount: 1)
        }
        for state in policy.expiredStates(from: all) {
            let thumbnail = try state.screenshotAssetID.flatMap { try assets.fetchAsset(id: $0) }
            if let asset = try assets.fetchAsset(id: state.stateAssetID) {
                let url = try assetStore.managedURL(relativePath: asset.relativePath)
                try states.deleteSaveState(id: state.id)
                try assets.deleteAsset(id: asset.id)
                try? assetStore.removeIfExists(url)
            } else {
                try states.deleteSaveState(id: state.id)
            }
            if let thumbnail { assets.discard(thumbnail, files: assetStore) }
        }
    }
}
