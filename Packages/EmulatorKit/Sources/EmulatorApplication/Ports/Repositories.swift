import Foundation
import EmulatorDomain

public protocol GameRepository: Sendable {
    func fetchGame(id: UUID) throws -> Game?
    func fetchGames() throws -> [Game]
    func insertGame(_ game: Game) throws
    func updateGame(_ game: Game) throws
    func deleteGame(id: UUID) throws
}

public protocol BuildRepository: Sendable {
    func fetchBuild(id: UUID) throws -> Build?
    func fetchBuilds(gameID: UUID) throws -> [Build]
    func fetchBuild(gameID: UUID, imageSHA256: String) throws -> Build?
    func fetchBuild(imageSHA256: String) throws -> Build?
    func insertBuild(_ build: Build) throws
    func updateBuildMetadata(_ build: Build) throws
    func moveBuild(id: UUID, toGameID: UUID) throws
}

public protocol SaveProfileRepository: Sendable {
    func fetchSaveProfile(id: UUID) throws -> SaveProfile?
    func fetchSaveProfiles(gameID: UUID) throws -> [SaveProfile]
    func insertSaveProfile(_ profile: SaveProfile) throws
    func updateSaveProfile(_ profile: SaveProfile) throws
    func deleteSaveProfile(id: UUID) throws
}

public protocol SaveStateRepository: Sendable {
    func insertSaveState(_ state: SaveState) throws
    func fetchSaveStates(buildID: UUID, saveProfileID: UUID) throws -> [SaveState]
    func deleteSaveState(id: UUID) throws
}

public protocol PatchRecipeRepository: Sendable {
    func insertPatchRecipe(_ recipe: PatchRecipe) throws
    func fetchPatchRecipe(resultBuildID: UUID) throws -> PatchRecipe?
}

public protocol ManagedAssetRepository: Sendable {
    func fetchAsset(id: UUID) throws -> ManagedAsset?
    func fetchSourceAsset(kind: ManagedAssetKind, sha256: String) throws -> ManagedAsset?
    /// Managed paths are unique, so this finds the record a content-addressed file already has.
    func fetchAsset(relativePath: String) throws -> ManagedAsset?
    func insertAsset(_ asset: ManagedAsset) throws
    func updateMutableAsset(_ asset: ManagedAsset) throws
    func deleteAsset(id: UUID) throws
}

/// Adds full inventory access for maintenance jobs such as library integrity scans.
/// Normal use cases intentionally depend on `ManagedAssetRepository` instead.
public protocol ManagedAssetInventoryRepository: ManagedAssetRepository {
    func fetchAssets() throws -> [ManagedAsset]
}
