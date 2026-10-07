import EmulatorDomain
import Foundation
import GameIdentity

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
    /// Nil only for analyses made before SHA-1 was computed, such as in tests.
    public let imageSHA1: String?
    /// The No-Intro game the image is a copy of, when it is one. `filenameMetadata` then comes from
    /// No-Intro's fields instead of the file's name, which stays in `originalFilename`.
    public let knownDump: KnownDump?
    /// The image as No-Intro lists it, which says whether it is a bad copy.
    public let knownFile: KnownDumpFile?
    /// The Games already holding a Build from the dump's family. With exactly one, it is the
    /// suggested Game; with several, the player chooses.
    public let familyGameIDs: [UUID]
    public let familyTitles: [String]
    public let baseLineageGameIDs: [UUID]
    /// The Games holding an imported Build whose ROM header has the same title. Homebrew keeps its
    /// header title from build to build, so a new build finds its project's Game even when the
    /// filename doesn't match. With exactly one, review suggests it.
    public let headerTitleGameIDs: [UUID]

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
        toolchainReports: [ToolchainDetectionReport] = [],
        imageSHA1: String? = nil,
        knownDump: KnownDump? = nil,
        knownFile: KnownDumpFile? = nil,
        familyGameIDs: [UUID] = [],
        familyTitles: [String] = [],
        baseLineageGameIDs: [UUID] = [],
        headerTitleGameIDs: [UUID] = []
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
        self.imageSHA1 = imageSHA1
        self.knownDump = knownDump
        self.knownFile = knownFile
        self.headerTitleGameIDs = headerTitleGameIDs
        self.familyGameIDs = familyGameIDs
        self.familyTitles = familyTitles
        self.baseLineageGameIDs = baseLineageGameIDs
    }
}

public struct ROMImportPlan: Equatable, Sendable {
    public let analysis: ROMImportAnalysis
    public let disposition: ROMImportDisposition
    public let buildDisplayName: String
    public let suggestedBuildDisplayName: String
    public let markAsBase: Bool
    public let markAsPreferred: Bool
    public let metadata: BuildImportMetadata
    public let proposedGameTitle: String?
    /// The player edited the proposed title, so it replaces even a title they set before.
    public let proposedGameTitleIsPlayers: Bool
    public let hasPlayerTitle: Bool
    public let baseGameReference: BaseGameReference?

    public init(
        analysis: ROMImportAnalysis,
        disposition: ROMImportDisposition,
        buildDisplayName: String,
        markAsBase: Bool,
        markAsPreferred: Bool = false,
        metadata: BuildImportMetadata? = nil,
        proposedGameTitle: String? = nil,
        proposedGameTitleIsPlayers: Bool = false,
        hasPlayerTitle: Bool = false,
        baseGameReference: BaseGameReference? = nil,
        suggestedBuildDisplayName: String? = nil
    ) {
        self.analysis = analysis
        self.disposition = disposition
        self.buildDisplayName = buildDisplayName
        self.suggestedBuildDisplayName = suggestedBuildDisplayName ?? analysis.filenameMetadata.suggestedBuildName
        self.markAsBase = markAsBase
        self.markAsPreferred = markAsPreferred
        var suggestedMetadata = BuildImportMetadata(analysis: analysis)
        if let baseGameReference { suggestedMetadata.baseTitle = baseGameReference.title }
        self.metadata = metadata ?? suggestedMetadata
        self.proposedGameTitle = proposedGameTitle
        self.proposedGameTitleIsPlayers = proposedGameTitleIsPlayers
        self.hasPlayerTitle = hasPlayerTitle
        self.baseGameReference = baseGameReference
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
