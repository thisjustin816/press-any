import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing

public enum QuickPlayWorkspaceError: Error, Equatable {
    case saveProfileNotFound(UUID)
    case persistentSaveAssetNotFound(UUID)
    case sessionNotFound(UUID)
    case malformedManifest(UUID)
}

public struct QuickPlayWorkspace: Sendable {
    private let profiles: any SaveProfileRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private let retentionSeconds: TimeInterval

    public init(
        profiles: any SaveProfileRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        retentionSeconds: TimeInterval = 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.profiles = profiles
        self.assets = assets
        self.assetStore = assetStore
        self.retentionSeconds = retentionSeconds
        self.now = now
        self.makeID = makeID
    }

    public func start(
        romURL: URL,
        copiedSaveProfileID: UUID? = nil
    ) throws -> QuickPlaySession {
        try ImportSizeLimit.rom.check(fileAt: romURL)
        let id = makeID()
        let root = assetStore.quickPlayRoot(sessionID: id)
        let destinationROM = root.appendingPathComponent("rom.bin")

        do {
            // Time to first frame is Quick Play's primary metric (docs/decisions.md): read the
            // image once and validate, copy and hash that same buffer.
            let romData = try assetStore.readData(at: romURL)
            let header = try GBROMHeaderParser.parse(romData)
            try assetStore.writeDataAtomically(romData, to: destinationROM)
            let startedAt = now()
            let session = QuickPlaySession(
                id: id,
                imageSHA256: assetStore.hashData(romData),
                originalFilename: romURL.lastPathComponent,
                system: header.system,
                rootURL: root,
                startedAt: startedAt,
                expiresAt: startedAt.addingTimeInterval(retentionSeconds),
                sourceSaveProfileID: copiedSaveProfileID
            )

            if let copiedSaveProfileID {
                try copyPersistentSave(profileID: copiedSaveProfileID, to: session.persistentSaveURL)
            }

            try persist(session)
            return session
        } catch {
            try? assetStore.removeIfExists(root)
            throw error
        }
    }

    public func load(sessionID: UUID) throws -> QuickPlaySession {
        let root = assetStore.quickPlayRoot(sessionID: sessionID)
        let manifest = root.appendingPathComponent("session.json")
        guard assetStore.fileExists(at: manifest) else {
            throw QuickPlayWorkspaceError.sessionNotFound(sessionID)
        }
        let stored: QuickPlaySession
        do {
            stored = try Self.decoder.decode(QuickPlaySession.self, from: assetStore.readData(at: manifest))
        } catch {
            throw QuickPlayWorkspaceError.malformedManifest(sessionID)
        }
        // The app's data directory can move between launches, for example after an update, so
        // the recorded absolute root is replaced by the session's current location.
        return QuickPlaySession(
            id: stored.id,
            imageSHA256: stored.imageSHA256,
            originalFilename: stored.originalFilename,
            system: stored.system,
            rootURL: root,
            startedAt: stored.startedAt,
            expiresAt: stored.expiresAt,
            sourceSaveProfileID: stored.sourceSaveProfileID
        )
    }

    /// Sessions still within retention, newest first. Unreadable manifests are skipped.
    public func sessions() throws -> [QuickPlaySession] {
        let current = now()
        return try assetStore.quickPlaySessionIDs()
            .compactMap { try? load(sessionID: $0) }
            .filter { $0.expiresAt > current }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public func writeTemporaryBattery(_ data: Data, sessionID: UUID) throws {
        let session = try load(sessionID: sessionID)
        try assetStore.writeDataAtomically(data, to: session.persistentSaveURL)
    }

    public func temporaryBatteryData(sessionID: UUID) throws -> Data? {
        let session = try load(sessionID: sessionID)
        guard assetStore.fileExists(at: session.persistentSaveURL) else { return nil }
        return try assetStore.readData(at: session.persistentSaveURL)
    }

    public func discard(sessionID: UUID) throws {
        try assetStore.removeIfExists(assetStore.quickPlayRoot(sessionID: sessionID))
    }

    private func copyPersistentSave(profileID: UUID, to destination: URL) throws {
        guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
            throw QuickPlayWorkspaceError.saveProfileNotFound(profileID)
        }
        guard let assetID = profile.persistentSaveAssetID else { return }
        guard let asset = try assets.fetchAsset(id: assetID) else {
            throw QuickPlayWorkspaceError.persistentSaveAssetNotFound(assetID)
        }
        let source = try assetStore.managedURL(relativePath: asset.relativePath)
        try assetStore.copyFileAtomically(from: source, to: destination)
    }

    private func persist(_ session: QuickPlaySession) throws {
        try assetStore.writeDataAtomically(try Self.encoder.encode(session), to: session.manifestURL)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
