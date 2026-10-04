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

public struct QuickPlayPromotionResult: Equatable, Sendable {
    public let importResult: ROMImportResult
    public let saveProfile: SaveProfile?
    /// The copy of a replaced profile taken before its save was overwritten.
    public let safetyCopy: SaveProfile?

    public init(importResult: ROMImportResult, saveProfile: SaveProfile?, safetyCopy: SaveProfile? = nil) {
        self.importResult = importResult
        self.saveProfile = saveProfile
        self.safetyCopy = safetyCopy
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
    private let profiles: any SaveProfileRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let persistentSaveService: PersistentSaveService
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        analyzer: ROMImportAnalyzer,
        committer: ImportCommitter,
        workspace: QuickPlayWorkspace,
        profiles: any SaveProfileRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.analyzer = analyzer
        self.committer = committer
        self.workspace = workspace
        self.profiles = profiles
        self.assets = assets
        self.assetStore = assetStore
        self.persistentSaveService = PersistentSaveService(profiles: profiles, assets: assets, assetStore: assetStore, now: now)
        self.now = now
        self.makeID = makeID
    }

    public func analyze(_ session: QuickPlaySession, targetGameID: UUID?) throws -> ROMImportAnalysis {
        try analyzer.analyzeROM(at: session.imageURL, targetGameID: targetGameID)
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
        // Promotion is complete; a sandbox left behind is removed by retention.
        try? workspace.discard(sessionID: session.id)
        return QuickPlayPromotionResult(importResult: result, saveProfile: promotedProfile, safetyCopy: safetyCopy)
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
