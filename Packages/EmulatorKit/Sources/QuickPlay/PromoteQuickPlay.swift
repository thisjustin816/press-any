import EmulationSession
import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing

public enum QuickPlaySaveDisposition: Equatable, Sendable {
    case keepExisting
    case replaceExisting(profileID: UUID)
    case createProfile(name: String)
}

/// A step after the save that didn't finish. The Build and its save are in the library either way.
public enum QuickPlayPromotionShortfall: Equatable, Hashable, Sendable {
    /// The session's resume point couldn't be moved to the library, so the session is kept and
    /// can still be continued from Quick Play.
    case resumePointNotMoved
    /// The promoted Build couldn't be set to play the kept save, so Play may pick another one.
    case buildDefaultSaveNotSet
}

public struct QuickPlayPromotionResult: Equatable, Sendable {
    public let importResult: ROMImportResult
    /// The promoted Build as it stands now, with the kept save as its default.
    public let build: Build
    public let saveProfile: SaveProfile?
    /// The copy of a replaced profile taken before its save was overwritten.
    public let safetyCopy: SaveProfile?
    public let shortfalls: Set<QuickPlayPromotionShortfall>

    public init(
        importResult: ROMImportResult,
        build: Build? = nil,
        saveProfile: SaveProfile?,
        safetyCopy: SaveProfile? = nil,
        shortfalls: Set<QuickPlayPromotionShortfall> = []
    ) {
        self.importResult = importResult
        self.build = build ?? importResult.build
        self.saveProfile = saveProfile
        self.safetyCopy = safetyCopy
        self.shortfalls = shortfalls
    }
}

public enum PromoteQuickPlayError: Error, Equatable {
    case temporaryBatteryMissing(UUID)
    case profileNotFound(UUID)
    /// A save can only replace a profile of the Game the Build is promoted into.
    case profileInDifferentGame(profileID: UUID)
    /// The Build is in the library but the save step failed. The session is kept, so promoting it
    /// again, from a fresh analysis, finds the Build already imported and only redoes the save.
    case importedButSaveFailed(gameID: UUID, buildID: UUID)
}

public struct PromoteQuickPlay: Sendable {
    private let analyzer: ROMImportAnalyzer
    private let committer: ImportCommitter
    private let workspace: QuickPlayWorkspace
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let states: any SaveStateRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let persistentSaveService: PersistentSaveService
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        analyzer: ROMImportAnalyzer,
        committer: ImportCommitter,
        workspace: QuickPlayWorkspace,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        states: any SaveStateRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.analyzer = analyzer
        self.committer = committer
        self.workspace = workspace
        self.builds = builds
        self.profiles = profiles
        self.states = states
        self.assets = assets
        self.assetStore = assetStore
        self.persistentSaveService = PersistentSaveService(profiles: profiles, assets: assets, assetStore: assetStore, now: now)
        self.now = now
        self.makeID = makeID
    }

    public func analyze(_ session: QuickPlaySession, targetGameID: UUID?) throws -> ROMImportAnalysis {
        try analyzer.analyzeROM(at: session.imageURL, targetGameID: targetGameID, originalFilename: session.originalFilename)
    }

    public func promote(
        session: QuickPlaySession,
        plan: ROMImportPlan,
        saveDisposition: QuickPlaySaveDisposition
    ) throws -> QuickPlayPromotionResult {
        // Check a replacement before committing, so a refused one leaves nothing half-imported.
        var replacement: (profile: SaveProfile, battery: Data)?
        if case .replaceExisting(let profileID) = saveDisposition {
            guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
                throw PromoteQuickPlayError.profileNotFound(profileID)
            }
            switch plan.disposition {
            case .createGame:
                throw PromoteQuickPlayError.profileInDifferentGame(profileID: profileID)
            case .addBuild(let gameID) where gameID != profile.gameID:
                throw PromoteQuickPlayError.profileInDifferentGame(profileID: profileID)
            default:
                break
            }
            guard let battery = try workspace.temporaryBatteryData(sessionID: session.id) else {
                throw PromoteQuickPlayError.temporaryBatteryMissing(session.id)
            }
            replacement = (profile, battery)
        }

        let result = try committer.commit(plan)
        let promotedProfile: SaveProfile?
        var safetyCopy: SaveProfile?
        do {
            switch saveDisposition {
            case .keepExisting:
                promotedProfile = nil
            case .replaceExisting(let profileID):
                guard let replacement, replacement.profile.gameID == result.game.id else {
                    throw PromoteQuickPlayError.profileInDifferentGame(profileID: profileID)
                }
                safetyCopy = try DuplicateSaveProfile(
                    profiles: profiles,
                    assets: assets,
                    assetStore: assetStore,
                    now: now,
                    makeID: makeID
                ).execute(
                    sourceProfileID: profileID,
                    name: "\(replacement.profile.displayName) before Quick Play"
                )
                do {
                    promotedProfile = try persistentSaveService.replacePersistentSaveData(
                        replacement.battery,
                        profileID: profileID,
                        writtenByBuildID: result.build.id
                    )
                } catch {
                    // The profile still has its old save, so the copy isn't needed, and a retry
                    // would otherwise make another.
                    if let copy = safetyCopy { profiles.discardNewProfile(copy, assets: assets, files: assetStore) }
                    throw error
                }
            case .createProfile(let name):
                promotedProfile = try createProfile(
                    gameID: result.game.id,
                    name: name,
                    temporaryBattery: try workspace.temporaryBatteryData(sessionID: session.id),
                    writtenByBuildID: result.build.id
                )
            }
        } catch let error as PromoteQuickPlayError {
            throw error
        } catch {
            throw PromoteQuickPlayError.importedButSaveFailed(gameID: result.game.id, buildID: result.build.id)
        }
        // The Build and its save are in the library now, so what follows can't undo them. Each
        // step that doesn't finish is reported instead, and the session is kept while it still
        // holds the only copy of the resume point.
        var build = result.build
        var shortfalls: Set<QuickPlayPromotionShortfall> = []
        if let promotedProfile {
            do {
                try adoptAutoState(of: session, buildID: result.build.id, profileID: promotedProfile.id)
            } catch {
                shortfalls.insert(.resumePointNotMoved)
            }
            // Play on this Build continues what was kept, even when the Build was already in the
            // library. The Game's default and other Builds stay as they were.
            do {
                build = try setDefaultSave(promotedProfile.id, buildID: result.build.id)
            } catch {
                shortfalls.insert(.buildDefaultSaveNotSet)
            }
        }
        if !shortfalls.contains(.resumePointNotMoved) {
            // Promotion is complete; a sandbox left behind is removed by retention.
            try? workspace.discard(sessionID: session.id)
        }
        return QuickPlayPromotionResult(
            importResult: result,
            build: build,
            saveProfile: promotedProfile,
            safetyCopy: safetyCopy,
            shortfalls: shortfalls
        )
    }

    private func setDefaultSave(_ profileID: UUID, buildID: UUID) throws -> Build {
        struct BuildMissing: Error {}
        guard var build = try builds.fetchBuild(id: buildID) else { throw BuildMissing() }
        guard build.preferredSaveProfileID != profileID else { return build }
        build.preferredSaveProfileID = profileID
        build.modifiedAt = now()
        try builds.updateBuildMetadata(build)
        return build
    }

    /// Brings the session's autosave in as the Build's Auto State for the promoted profile, so the
    /// first launch resumes there under the usual Resume Games policy. An autosave taken before
    /// the session's battery save was last written is left out, as it would roll that save back.
    private func adoptAutoState(of session: QuickPlaySession, buildID: UUID, profileID: UUID) throws {
        guard assetStore.fileExists(at: session.autoStateURL),
              let record = session.autoStateRecord(files: assetStore),
              !session.batteryIsNewerThanAutoState(files: assetStore)
        else { return }
        let payload = try assetStore.readData(at: session.autoStateURL)
        let stateID = makeID()
        let destination = assetStore.stateURL(stateID: stateID)
        let relativePath = try assetStore.managedRelativePath(for: destination)
        try assetStore.writeDataAtomically(payload, to: destination)

        // Taken after the save was written, so the newer-save check offers it.
        let timestamp = now()
        let asset = ManagedAsset(
            id: makeID(),
            kind: .saveState,
            storageClass: .userData,
            contentSHA256: assetStore.hashData(payload),
            byteLength: Int64(payload.count),
            relativePath: relativePath,
            integrityStatus: .verified,
            createdAt: timestamp
        )
        do {
            try assets.insertAsset(asset)
            do {
                let existing = try states.fetchSaveStates(buildID: buildID, saveProfileID: profileID)
                try states.insertSaveState(SaveState(
                    id: stateID,
                    buildID: buildID,
                    saveProfileID: profileID,
                    core: record.core,
                    stateSerializationVersion: record.stateSerializationVersion,
                    stateAssetID: asset.id,
                    kind: .auto,
                    autoSequence: (existing.compactMap(\.autoSequence).max() ?? 0) + 1,
                    playtimeSeconds: record.playtimeSeconds,
                    createdAt: timestamp
                ))
            } catch {
                try? assets.deleteAsset(id: asset.id)
                throw error
            }
        } catch {
            try? assetStore.removeIfExists(destination)
            throw error
        }
    }

    private func createProfile(gameID: UUID, name: String, temporaryBattery: Data?, writtenByBuildID: UUID) throws -> SaveProfile {
        let timestamp = now()
        var profile = SaveProfile(
            id: makeID(),
            gameID: gameID,
            displayName: name,
            createdAt: timestamp,
            modifiedAt: timestamp
        )
        try profiles.insertSaveProfile(profile)
        do {
            if let temporaryBattery, !temporaryBattery.isEmpty {
                profile = try persistentSaveService.replacePersistentSaveData(
                    temporaryBattery,
                    profileID: profile.id,
                    writtenByBuildID: writtenByBuildID
                )
            }
            return profile
        } catch {
            try? profiles.deleteSaveProfile(id: profile.id)
            throw error
        }
    }
}
