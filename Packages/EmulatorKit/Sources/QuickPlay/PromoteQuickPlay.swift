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

    public init(importResult: ROMImportResult, saveProfile: SaveProfile?) {
        self.importResult = importResult
        self.saveProfile = saveProfile
    }
}

public enum PromoteQuickPlayError: Error, Equatable {
    case temporaryBatteryMissing(UUID)
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
        let result = try committer.commit(plan)
        let promotedProfile: SaveProfile?
        switch saveDisposition {
        case .keepExisting:
            promotedProfile = nil
        case .replaceExisting(let profileID):
            guard let battery = try workspace.temporaryBatteryData(sessionID: session.id) else {
                throw PromoteQuickPlayError.temporaryBatteryMissing(session.id)
            }
            promotedProfile = try persistentSaveService.replacePersistentSaveData(battery, profileID: profileID)
        case .createProfile(let name):
            promotedProfile = try createProfile(
                gameID: result.game.id,
                name: name,
                temporaryBattery: try workspace.temporaryBatteryData(sessionID: session.id)
            )
        }
        try workspace.discard(sessionID: session.id)
        return QuickPlayPromotionResult(importResult: result, saveProfile: promotedProfile)
    }

    private func createProfile(gameID: UUID, name: String, temporaryBattery: Data?) throws -> SaveProfile {
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
                profile = try persistentSaveService.replacePersistentSaveData(temporaryBattery, profileID: profile.id)
            }
            return profile
        } catch {
            try? profiles.deleteSaveProfile(id: profile.id)
            throw error
        }
    }
}
