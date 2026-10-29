import EmulatorDomain
import Foundation

public struct BackupManualPosition: Codable, Equatable, Sendable {
    public var gameID: UUID
    public var position: Int

    public init(gameID: UUID, position: Int) {
        self.gameID = gameID
        self.position = position
    }
}

public struct BackupSetting: Codable, Equatable, Sendable {
    public static let excludedKeys: Set<String> = [
        "session.launchMarker", "backup.lastRestoreReport", "noIntro.appliedVersion",
    ]

    public var scopeType: String
    public var scopeID: String
    public var key: String
    public var valueJSON: String

    public init(scopeType: String, scopeID: String, key: String, valueJSON: String) {
        self.scopeType = scopeType
        self.scopeID = scopeID
        self.key = key
        self.valueJSON = valueJSON
    }

    public var identity: String { "\(scopeType)/\(scopeID)/\(key)" }
}

public struct BackupProvenance: Codable, Equatable, Sendable {
    public var ownerID: UUID
    public var values: [MetadataProvenance]

    public init(ownerID: UUID, values: [MetadataProvenance]) {
        self.ownerID = ownerID
        self.values = values
    }
}

public struct BackupToolchainReport: Codable, Equatable, Sendable {
    public var buildID: UUID
    public var report: ToolchainDetectionReport
    public var detectedAt: Date

    public init(buildID: UUID, report: ToolchainDetectionReport, detectedAt: Date) {
        self.buildID = buildID
        self.report = report
        self.detectedAt = detectedAt
    }

    public var identity: String { "\(buildID.uuidString)/\(report.detector)" }
}

/// A source image's matching evidence, which Import Review uses to match a new Build to its Game.
/// It is derived from the ROM, but a backup without ROMs has nothing to derive it from, so it
/// travels with the Build's other records. Bank hashes are written as 16-digit hex, since JSON
/// numbers cannot hold a 64-bit hash exactly everywhere.
public struct BackupImageFingerprint: Codable, Equatable, Sendable {
    public var fingerprint: ImageFingerprint

    public init(_ fingerprint: ImageFingerprint) { self.fingerprint = fingerprint }

    public var identity: String { fingerprint.imageSHA256 }

    private enum CodingKeys: String, CodingKey {
        case imageSHA256, bankSize, bankHashes, headerTitle, cartridgeType, ramSizeCode, cgbFlag
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let hashes = try values.decode([String].self, forKey: .bankHashes).map { text -> UInt64 in
            guard text.count == 16, let hash = UInt64(text, radix: 16) else {
                throw DecodingError.dataCorruptedError(forKey: .bankHashes, in: values,
                    debugDescription: "\(text) is not a bank hash")
            }
            return hash
        }
        fingerprint = ImageFingerprint(
            imageSHA256: try values.decode(String.self, forKey: .imageSHA256),
            bankSize: try values.decode(Int.self, forKey: .bankSize), bankHashes: hashes,
            headerTitle: try values.decode(String.self, forKey: .headerTitle),
            cartridgeType: try values.decode(UInt8.self, forKey: .cartridgeType),
            ramSizeCode: try values.decode(UInt8.self, forKey: .ramSizeCode),
            cgbFlag: try values.decode(UInt8.self, forKey: .cgbFlag))
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fingerprint.imageSHA256, forKey: .imageSHA256)
        try values.encode(fingerprint.bankSize, forKey: .bankSize)
        try values.encode(fingerprint.bankHashes.map { String(format: "%016llx", $0) }, forKey: .bankHashes)
        try values.encode(fingerprint.headerTitle, forKey: .headerTitle)
        try values.encode(fingerprint.cartridgeType, forKey: .cartridgeType)
        try values.encode(fingerprint.ramSizeCode, forKey: .ramSizeCode)
        try values.encode(fingerprint.cgbFlag, forKey: .cgbFlag)
    }
}

/// Destination records outside the live library. They never travel in a backup; restore uses
/// them to leave deleted records alone and to reuse asset rows that already hold a file.
public struct RetainedLibraryRecords: Equatable, Sendable {
    /// Games, Builds, Save Profiles, Save States, prints, recipes, variable maps and cheats that are in
    /// Recently Deleted or were deleted for good.
    public var recordIDs: Set<UUID>
    /// Every asset row the live records don't reference, ordered by ID.
    public var assets: [ManagedAsset]

    public init(recordIDs: Set<UUID> = [], assets: [ManagedAsset] = []) {
        self.recordIDs = recordIDs
        self.assets = assets
    }
}

public struct LibraryBackupSnapshot: Equatable, Sendable {
    public var migrationID: String
    public var games: [Game] = []
    public var manualPositions: [BackupManualPosition] = []
    public var builds: [Build] = []
    public var profiles: [SaveProfile] = []
    public var states: [SaveState] = []
    public var recipes: [PatchRecipe] = []
    public var variableMaps: [BuildVariableMap] = []
    public var cheats: [BuildCheat] = []
    public var captures: [Capture] = []
    public var assets: [ManagedAsset] = []
    public var gameProvenance: [BackupProvenance] = []
    public var buildProvenance: [BackupProvenance] = []
    public var reports: [BackupToolchainReport] = []
    public var declarations: [BuildSaveDeclaration] = []
    /// The evidence of the live Builds' source images. A restore keeps only the evidence of an image
    /// a restored Build uses, and never replaces evidence the library already has.
    public var fingerprints: [BackupImageFingerprint] = []
    public var settings: [BackupSetting] = []
    public var retained = RetainedLibraryRecords()

    public init(migrationID: String = "") { self.migrationID = migrationID }
}

public protocol LibraryBackupRepository: Sendable {
    /// Reads every live record from one database snapshot. Files are read by the caller while
    /// this callback runs, so metadata cannot change between its read and the file copy.
    func readSnapshot<T: Sendable>(_ operation: @Sendable (LibraryBackupSnapshot) throws -> T) throws -> T

    /// Runs the comparison and writes together. Throwing leaves metadata and the prior report
    /// unchanged. Merge preserves Recently Deleted and removes asset rows that only the replaced
    /// live records referenced; replacement clears Recently Deleted.
    func commitSnapshot<T: Sendable>(
        replacingLibrary: Bool,
        _ operation: @Sendable (LibraryBackupSnapshot) throws -> (LibraryBackupSnapshot, RestoreReport, T)
    ) throws -> T

    func lastRestoreReport() throws -> RestoreReport?
}
