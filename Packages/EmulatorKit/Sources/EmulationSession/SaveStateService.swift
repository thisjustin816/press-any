import EmulatorApplication
import EmulatorDomain
import EmulationCore
import Foundation

public enum SaveStateServiceError: Error, Equatable {
    case contextMismatch
    case coreMismatch(expected: CoreDescriptor, actual: CoreDescriptor)
    case serializationVersionMismatch(expected: String, actual: String)
    case assetNotFound(UUID)
}

public struct SaveStateService: Sendable {
    private let states: any SaveStateRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let retention: AutoStateRetention
    private let thumbnails: (any FrameImageEncoding)?
    private let now: @Sendable () -> Date

    public init(
        states: any SaveStateRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        retention: AutoStateRetention = .init(),
        thumbnails: (any FrameImageEncoding)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.states = states
        self.assets = assets
        self.assetStore = assetStore
        self.retention = retention
        self.thumbnails = thumbnails
        self.now = now
    }

    @discardableResult
    public func save(
        worker: SessionWorker,
        context: LaunchContext,
        kind: SaveStateKind,
        label: String? = nil,
        playtimeSeconds: Double,
        frame: EmulatorVideoFrame? = nil
    ) throws -> SaveState {
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
        let thumbnail = frame.flatMap { try? saveThumbnail($0, stateID: stateID, timestamp: timestamp) }

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
                state = SaveState(
                    id: stateID,
                    buildID: context.buildID,
                    saveProfileID: context.saveProfileID,
                    core: core,
                    stateSerializationVersion: serializationVersion,
                    stateAssetID: assetID,
                    screenshotAssetID: thumbnail?.id,
                    kind: kind,
                    autoSequence: autoSequence,
                    label: label,
                    playtimeSeconds: playtimeSeconds,
                    createdAt: timestamp
                )
                try states.insertSaveState(state)
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
        }
        return state
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

        guard let asset = try assets.fetchAsset(id: state.stateAssetID) else {
            throw SaveStateServiceError.assetNotFound(state.stateAssetID)
        }
        let url = try assetStore.managedURL(relativePath: asset.relativePath)
        let payload = try assetStore.readData(at: url)
        try worker.perform { try $0.deserializeState(payload) }
    }

    private func pruneAutoStates(context: LaunchContext) throws {
        let all = try states.fetchSaveStates(buildID: context.buildID, saveProfileID: context.saveProfileID)
        for state in retention.expiredStates(from: all) {
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
