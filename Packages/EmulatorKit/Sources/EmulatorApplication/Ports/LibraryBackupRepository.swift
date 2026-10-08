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

/// Destination records outside the live library. They never travel in a backup; restore uses
/// them to leave deleted records alone and to reuse asset rows that already hold a file.
public struct RetainedLibraryRecords: Equatable, Sendable {
    /// Games, Builds, Save Profiles, Save States, recipes and variable maps that are in Recently
    /// Deleted or were deleted for good.
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
    public var assets: [ManagedAsset] = []
    public var gameProvenance: [BackupProvenance] = []
    public var buildProvenance: [BackupProvenance] = []
    public var reports: [BackupToolchainReport] = []
    public var declarations: [BuildSaveDeclaration] = []
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
