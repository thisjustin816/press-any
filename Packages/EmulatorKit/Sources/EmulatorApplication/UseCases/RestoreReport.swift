import Foundation

public enum RestoreChoice: String, Codable, CaseIterable, Sendable {
    case library
    case archive
    case keepBoth
}

public struct RestoreResolution: Codable, Equatable, Sendable {
    public var record: String
    public var choice: RestoreChoice

    public init(record: String, choice: RestoreChoice) {
        self.record = record
        self.choice = choice
    }
}

public struct RestoreMissingROM: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct RestoreReport: Codable, Equatable, Sendable {
    public var restoredAt: Date
    public var added: Int
    public var skipped: Int
    public var resolutions: [RestoreResolution]
    public var missingROMs: [RestoreMissingROM]
    public var notCarriedOver: [String]

    public init(restoredAt: Date, added: Int = 0, skipped: Int = 0,
                resolutions: [RestoreResolution] = [], missingROMs: [RestoreMissingROM] = [],
                notCarriedOver: [String] = []) {
        self.restoredAt = restoredAt
        self.added = added
        self.skipped = skipped
        self.resolutions = resolutions
        self.missingROMs = missingROMs
        self.notCarriedOver = notCarriedOver
    }
}
