import EmulatorApplication
import EmulatorDomain
import Foundation

public struct BackupFileInfo: Codable, Equatable, Sendable {
    public var sha256: String
    public var byteLength: Int64

    public init(sha256: String, byteLength: Int64) {
        self.sha256 = sha256
        self.byteLength = byteLength
    }
}

public struct LibraryBackupManifest: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public var formatVersion: Int
    public var appVersion: String
    public var appBuild: String
    public var migrationID: String
    public var createdAt: Date
    public var includesROMs: Bool
    public var isEncrypted: Bool
    public var isGamePackage: Bool
    public var gameID: UUID?
    public var recordCounts: [String: Int]
    public var files: [String: BackupFileInfo]
    public var notCarriedOver: [String]

    public init(appVersion: String, appBuild: String, migrationID: String, createdAt: Date,
                includesROMs: Bool, gameID: UUID? = nil, recordCounts: [String: Int],
                files: [String: BackupFileInfo], notCarriedOver: [String] = []) {
        formatVersion = Self.currentFormatVersion
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.migrationID = migrationID
        self.createdAt = createdAt
        self.includesROMs = includesROMs
        isEncrypted = false
        isGamePackage = gameID != nil
        self.gameID = gameID
        self.recordCounts = recordCounts
        self.files = files
        self.notCarriedOver = notCarriedOver
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        appVersion = try values.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        appBuild = try values.decodeIfPresent(String.self, forKey: .appBuild) ?? ""
        migrationID = try values.decodeIfPresent(String.self, forKey: .migrationID) ?? ""
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        includesROMs = try values.decodeIfPresent(Bool.self, forKey: .includesROMs) ?? false
        isEncrypted = try values.decodeIfPresent(Bool.self, forKey: .isEncrypted) ?? false
        isGamePackage = try values.decodeIfPresent(Bool.self, forKey: .isGamePackage) ?? false
        gameID = try values.decodeIfPresent(UUID.self, forKey: .gameID)
        recordCounts = try values.decodeIfPresent([String: Int].self, forKey: .recordCounts) ?? [:]
        files = try values.decode([String: BackupFileInfo].self, forKey: .files)
        notCarriedOver = try values.decodeIfPresent([String].self, forKey: .notCarriedOver) ?? []
    }
}

public struct BackupSummary: Equatable, Sendable {
    public var recordCounts: [String: Int]
    public var approximateByteLength: Int64
}

public struct PreparedLibraryRestore: Sendable {
    public let manifest: LibraryBackupManifest
    public let snapshot: LibraryBackupSnapshot
    let files: [String: Data]
}

public struct LibraryRestoreConflict: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let name: String
    public let suggestedChoice: RestoreChoice
    public let allowsKeepBoth: Bool
    public let requiresExplicitChoice: Bool
}

public struct LibraryRestoreReview: Equatable, Sendable {
    public let snapshot: LibraryBackupSnapshot
    public let added: Int
    public let skipped: Int
    public let conflicts: [LibraryRestoreConflict]
    public let missingROMs: [RestoreMissingROM]
}

public enum LibraryBackupError: LocalizedError, Equatable {
    case newerFormat
    case encrypted
    case invalidArchive(String)
    case missingFile(String)
    case checksumMismatch(String)
    case missingLibraryFile(String)
    case libraryChanged
    case unresolvedConflict(String)
    case unsafeChoice(String)
    case safetyBackupRequired

    public var errorDescription: String? {
        switch self {
        case .newerFormat: "This backup was made with a newer format. Update the app to restore it."
        case .encrypted: "This backup needs password support. Update the app to restore it."
        case .invalidArchive(let reason): "This backup cannot be restored: \(reason)."
        case .missingFile(let path): "This backup is missing \(path). The library has not changed."
        case .checksumMismatch(let path): "The checksum for \(path) does not match. The library has not changed."
        case .missingLibraryFile(let path): "The library is missing or has changed \(path). Check Library Files before backing up."
        case .libraryChanged: "The library changed during review. Review the backup again before restoring."
        case .unresolvedConflict(let name): "Choose which version of \(name) to keep."
        case .unsafeChoice(let name): "\(name) cannot be kept as a second copy."
        case .safetyBackupRequired: "Create the automatic backup before replacing the library."
        }
    }
}
