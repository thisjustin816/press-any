import Foundation

/// The kinds of record a deletion can take with it.
public enum LibraryRecordKind: String, Codable, Sendable, CaseIterable {
    case game
    case build
    case saveProfile
    case saveState
}

/// The records one deletion hides, and later purges.
public struct LibraryRecordSet: Equatable, Sendable {
    public var gameIDs: [UUID]
    public var buildIDs: [UUID]
    public var saveProfileIDs: [UUID]
    public var saveStateIDs: [UUID]

    public init(gameIDs: [UUID] = [], buildIDs: [UUID] = [], saveProfileIDs: [UUID] = [], saveStateIDs: [UUID] = []) {
        self.gameIDs = gameIDs
        self.buildIDs = buildIDs
        self.saveProfileIDs = saveProfileIDs
        self.saveStateIDs = saveStateIDs
    }

    public var isEmpty: Bool {
        gameIDs.isEmpty && buildIDs.isEmpty && saveProfileIDs.isEmpty && saveStateIDs.isEmpty
    }

    /// Every record with its kind, as tombstones list them.
    public var all: [(id: UUID, kind: LibraryRecordKind)] {
        gameIDs.map { ($0, .game) } + buildIDs.map { ($0, .build) }
            + saveProfileIDs.map { ($0, .saveProfile) } + saveStateIDs.map { ($0, .saveState) }
    }

    /// The same records in any order are the same set; a store may read them back sorted.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        Set(lhs.gameIDs) == Set(rhs.gameIDs) && Set(lhs.buildIDs) == Set(rhs.buildIDs)
            && Set(lhs.saveProfileIDs) == Set(rhs.saveProfileIDs) && Set(lhs.saveStateIDs) == Set(rhs.saveStateIDs)
    }
}

/// What the player deleted in one go: a Game, a Build, a Save Profile or a save state, with
/// whatever went with it. It stays in Recently Deleted, restorable, for `retention`, then its
/// records are purged.
public struct LibraryDeletion: Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case game
        case build
        case saveProfile
        case saveState
    }

    /// Thirty days.
    public static let retention: TimeInterval = 30 * 24 * 60 * 60

    public let id: UUID
    public let kind: Kind
    /// What Recently Deleted calls it, such as the Game's title or the Build's name.
    public let title: String
    /// The Game it came from. For a Game deletion, the Game itself.
    public let gameID: UUID
    public let deletedAt: Date
    public let records: LibraryRecordSet

    public init(id: UUID, kind: Kind, title: String, gameID: UUID, deletedAt: Date, records: LibraryRecordSet) {
        self.id = id
        self.kind = kind
        self.title = title
        self.gameID = gameID
        self.deletedAt = deletedAt
        self.records = records
    }

    public var purgeDate: Date { deletedAt.addingTimeInterval(Self.retention) }
}

/// A record that was purged for good. Tombstones are never removed, so a copy of the library that
/// was offline when the record went, such as another device's, can't bring it back.
public struct Tombstone: Equatable, Sendable {
    public let recordID: UUID
    public let kind: LibraryRecordKind
    public let deletedAt: Date
    public let purgedAt: Date

    public init(recordID: UUID, kind: LibraryRecordKind, deletedAt: Date, purgedAt: Date) {
        self.recordID = recordID
        self.kind = kind
        self.deletedAt = deletedAt
        self.purgedAt = purgedAt
    }
}
