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
    /// Every state made with the profile, on any Build.
    func fetchSaveStates(saveProfileID: UUID) throws -> [SaveState]
    /// Moves the Build's states made with one profile over to another.
    func reassignSaveStates(buildID: UUID, fromSaveProfileID: UUID, toSaveProfileID: UUID) throws
    func deleteSaveState(id: UUID) throws
}

/// Each Build keeps one report per detector, the latest it ran.
public protocol ToolchainReportRepository: Sendable {
    /// Inserts the report, or replaces the Build's earlier report from the same detector.
    func saveReport(_ report: ToolchainDetectionReport, buildID: UUID, detectedAt: Date) throws
    func fetchReports(buildID: UUID) throws -> [ToolchainDetectionReport]
}

public protocol BuildVariableMapRepository: Sendable {
    func insertVariableMap(_ map: BuildVariableMap) throws
    func fetchVariableMaps(buildID: UUID) throws -> [BuildVariableMap]
}

public protocol PatchRecipeRepository: Sendable {
    func insertPatchRecipe(_ recipe: PatchRecipe) throws
    func fetchPatchRecipe(resultBuildID: UUID) throws -> PatchRecipe?
    /// The recipes that patch this Build, whose results are rebuilt from it.
    func fetchPatchRecipes(baseBuildID: UUID) throws -> [PatchRecipe]
}

/// Recently Deleted. Every other repository read leaves out a deletion's records until it is
/// restored, and purging removes them for good.
public protocol LibraryDeletionRepository: Sendable {
    /// Records the deletion and hides its records.
    func insertDeletion(_ deletion: LibraryDeletion) throws
    /// Newest first.
    func fetchDeletions() throws -> [LibraryDeletion]
    /// Brings the records back. A restored Base Build stays Base only while its Game has no other.
    func restoreDeletion(id: UUID) throws
    /// Removes the deletion's records for good, with any deleted patched Build that can no longer
    /// be rebuilt without them, and leaves a tombstone for each. Returns the assets those records
    /// used that nothing uses now; their rows are gone, and the caller removes their files.
    func purgeDeletion(id: UUID, at date: Date) throws -> [ManagedAsset]
    func fetchTombstones() throws -> [Tombstone]
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
