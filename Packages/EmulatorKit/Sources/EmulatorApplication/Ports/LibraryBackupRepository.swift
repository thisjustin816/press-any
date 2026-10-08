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

    public init(migrationID: String = "") { self.migrationID = migrationID }
}

public protocol LibraryBackupRepository: Sendable {
    /// Reads every live record from one database snapshot. Files are read by the caller while
    /// this callback runs, so metadata cannot change between its read and the file copy.
    func readSnapshot<T: Sendable>(_ operation: @Sendable (LibraryBackupSnapshot) throws -> T) throws -> T

    /// Runs the comparison and writes together. Throwing leaves metadata and the prior report
    /// unchanged. Merge preserves Recently Deleted; replacement clears it.
    func commitSnapshot<T: Sendable>(
        replacingLibrary: Bool,
        _ operation: @Sendable (LibraryBackupSnapshot) throws -> (LibraryBackupSnapshot, RestoreReport, T)
    ) throws -> T

    func lastRestoreReport() throws -> RestoreReport?
}
