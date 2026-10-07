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
    /// suggested Game; with several, the player chooses (Q157).
    public let familyGameIDs: [UUID]

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
        familyGameIDs: [UUID] = []
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
        self.familyGameIDs = familyGameIDs
    }
}

public struct ROMImportPlan: Equatable, Sendable {
    public let analysis: ROMImportAnalysis
    public let disposition: ROMImportDisposition
    public let buildDisplayName: String
    public let markAsBase: Bool
    public let markAsPreferred: Bool
    public let metadata: BuildImportMetadata

    public init(
        analysis: ROMImportAnalysis,
        disposition: ROMImportDisposition,
        buildDisplayName: String,
        markAsBase: Bool,
        markAsPreferred: Bool = false,
        metadata: BuildImportMetadata? = nil
    ) {
        self.analysis = analysis
        self.disposition = disposition
        self.buildDisplayName = buildDisplayName
        self.markAsBase = markAsBase
        self.markAsPreferred = markAsPreferred
        self.metadata = metadata ?? BuildImportMetadata(analysis: analysis)
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
