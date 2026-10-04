import EmulatorDomain
import Foundation

public enum ROMImportDisposition: Equatable, Sendable {
    case createGame(title: String)
    case addBuild(gameID: UUID)
    case duplicateExisting(buildID: UUID)
}

public struct ROMImportAnalysis: Equatable, Sendable {
    public let transactionID: UUID
    public let stagedURL: URL
    public let originalFilename: String
    public let sha256: String
    public let byteLength: Int64
    public let header: GBROMHeader
    public let filenameMetadata: FilenameMetadata
    public let exactExistingBuildID: UUID?
    public let suggestedGameID: UUID?
    /// What each toolchain detector found in the image. Shown for review and stored on the Build;
    /// it never decides the Game.
    public let toolchainReports: [ToolchainDetectionReport]

    public init(
        transactionID: UUID,
        stagedURL: URL,
        originalFilename: String,
        sha256: String,
        byteLength: Int64,
        header: GBROMHeader,
        filenameMetadata: FilenameMetadata,
        exactExistingBuildID: UUID?,
        suggestedGameID: UUID?,
        toolchainReports: [ToolchainDetectionReport] = []
    ) {
        self.transactionID = transactionID
        self.stagedURL = stagedURL
        self.originalFilename = originalFilename
        self.sha256 = sha256
        self.byteLength = byteLength
        self.header = header
        self.filenameMetadata = filenameMetadata
        self.exactExistingBuildID = exactExistingBuildID
        self.suggestedGameID = suggestedGameID
        self.toolchainReports = toolchainReports
    }
}

public struct ROMImportPlan: Equatable, Sendable {
    public let analysis: ROMImportAnalysis
    public let disposition: ROMImportDisposition
    public let buildDisplayName: String
    public let markAsBase: Bool

    public init(
        analysis: ROMImportAnalysis,
        disposition: ROMImportDisposition,
        buildDisplayName: String,
        markAsBase: Bool
    ) {
        self.analysis = analysis
        self.disposition = disposition
        self.buildDisplayName = buildDisplayName
        self.markAsBase = markAsBase
    }
}

public struct ROMImportResult: Equatable, Sendable {
    public let game: Game
    public let build: Build
    public let sourceAsset: ManagedAsset
    public let createdNewGame: Bool
    public let createdNewBuild: Bool

    public init(
        game: Game,
        build: Build,
        sourceAsset: ManagedAsset,
        createdNewGame: Bool,
        createdNewBuild: Bool
    ) {
        self.game = game
        self.build = build
        self.sourceAsset = sourceAsset
        self.createdNewGame = createdNewGame
        self.createdNewBuild = createdNewBuild
    }
}
