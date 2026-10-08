import EmulatorDomain
import Foundation

public enum BuildCheatError: LocalizedError, Equatable {
    case missingName
    case noCodes
    /// Counted from 1, blank lines included, so it matches the line the player sees.
    case unreadableLine(Int)
    case cheatNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .missingName: "Give the cheat a name."
        case .noCodes: "Enter at least one code."
        case .unreadableLine(let line): "Line \(line) isn’t a Game Genie or GameShark code."
        case .cheatNotFound: "This cheat is no longer in the library."
        }
    }
}

/// Codes as the player types them: one per line, blank lines skipped.
public enum CheatCodeText {
    /// Each code trimmed and uppercased. `isValid` is the core's check; the first line it refuses
    /// stops the whole entry.
    public static func codes(in text: String, isValid: (String) -> Bool) throws -> [String] {
        var codes: [String] = []
        for (index, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let code = line.trimmingCharacters(in: .whitespaces).uppercased()
            guard !code.isEmpty else { continue }
            guard isValid(code) else { throw BuildCheatError.unreadableLine(index + 1) }
            codes.append(code)
        }
        guard !codes.isEmpty else { throw BuildCheatError.noCodes }
        return codes
    }

    public static func text(of codes: [String]) -> String {
        codes.joined(separator: "\n")
    }
}

/// Adding, editing, switching, reordering and deleting a Build's cheats. Every change records
/// the cheat's modifiedAt, which a restore uses to suggest the newer version.
public struct BuildCheatOperations: Sendable {
    private let builds: any BuildRepository
    private let cheats: any BuildCheatRepository
    private let transactions: any LibraryTransactionRunner
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        builds: any BuildRepository,
        cheats: any BuildCheatRepository,
        transactions: any LibraryTransactionRunner = PassthroughTransactionRunner(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.builds = builds
        self.cheats = cheats
        self.transactions = transactions
        self.now = now
        self.makeID = makeID
    }

    public func cheats(buildID: UUID) throws -> [BuildCheat] {
        try cheats.fetchCheats(buildID: buildID)
    }

    /// Adds the cheat, switched on, at the end of the Build's list. Nothing is saved unless the
    /// name is there and every line reads.
    @discardableResult
    public func add(buildID: UUID, name: String, codes text: String, isValid: (String) -> Bool) throws -> BuildCheat {
        let name = try Self.name(name)
        let codes = try CheatCodeText.codes(in: text, isValid: isValid)
        return try transactions.run { [builds, cheats, now, makeID] in
            guard try builds.fetchBuild(id: buildID) != nil else { throw BuildOperationError.buildNotFound(buildID) }
            let timestamp = now()
            let cheat = BuildCheat(id: makeID(), buildID: buildID, name: name, codes: codes,
                position: try cheats.fetchCheats(buildID: buildID).count, createdAt: timestamp, modifiedAt: timestamp)
            try cheats.insertCheat(cheat)
            return cheat
        }
    }

    @discardableResult
    public func edit(cheatID: UUID, name: String, codes text: String, isValid: (String) -> Bool) throws -> BuildCheat {
        let name = try Self.name(name)
        let codes = try CheatCodeText.codes(in: text, isValid: isValid)
        return try change(cheatID) { cheat in
            cheat.name = name
            cheat.codes = codes
        }
    }

    public func setEnabled(cheatID: UUID, _ isEnabled: Bool) throws {
        try change(cheatID) { $0.isEnabled = isEnabled }
    }

    /// Deletes the cheat for good; cheats don't go to Recently Deleted on their own.
    public func delete(cheatID: UUID) throws {
        try transactions.run { [cheats, now] in
            guard let cheat = try cheats.fetchCheat(id: cheatID) else { throw BuildCheatError.cheatNotFound(cheatID) }
            try cheats.deleteCheat(id: cheatID)
            try Self.number(try cheats.fetchCheats(buildID: cheat.buildID), cheats: cheats, at: now())
        }
    }

    /// Puts the Build's cheats in this order. A cheat the list leaves out keeps its place after the
    /// listed ones, so a list read before another change can't lose it.
    public func reorder(buildID: UUID, orderedIDs: [UUID]) throws {
        try transactions.run { [cheats, now] in
            let current = try cheats.fetchCheats(buildID: buildID)
            let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            var seen = Set<UUID>()
            let listed = orderedIDs.compactMap { id in seen.insert(id).inserted ? byID[id] : nil }
            try Self.number(listed + current.filter { !seen.contains($0.id) }, cheats: cheats, at: now())
        }
    }

    public func setCheatsEnabled(buildID: UUID, enabled: Bool) throws {
        try builds.setCheatsEnabled(buildID: buildID, enabled: enabled)
    }

    private static func name(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BuildCheatError.missingName }
        return trimmed
    }

    @discardableResult
    private func change(_ cheatID: UUID, _ update: @escaping @Sendable (inout BuildCheat) -> Void) throws -> BuildCheat {
        try transactions.run { [cheats, now] in
            guard var cheat = try cheats.fetchCheat(id: cheatID) else { throw BuildCheatError.cheatNotFound(cheatID) }
            update(&cheat)
            cheat.modifiedAt = now()
            try cheats.updateCheat(cheat)
            return cheat
        }
    }

    /// Gives the cheats positions 0, 1, 2... in this order, saving only those that moved.
    private static func number(_ ordered: [BuildCheat], cheats: any BuildCheatRepository, at date: Date) throws {
        for (position, cheat) in ordered.enumerated() where cheat.position != position {
            var moved = cheat
            moved.position = position
            moved.modifiedAt = date
            try cheats.updateCheat(moved)
        }
    }
}

extension BuildCheatRepository {
    /// Gives `targetBuildID` its own copy of each of the source Build's cheats, in the same order
    /// and with the same switches.
    func copyCheats(from sourceBuildID: UUID, to targetBuildID: UUID, at date: Date, makeID: () -> UUID) throws {
        for cheat in try fetchCheats(buildID: sourceBuildID) {
            try insertCheat(BuildCheat(id: makeID(), buildID: targetBuildID, name: cheat.name, codes: cheat.codes,
                isEnabled: cheat.isEnabled, position: cheat.position, createdAt: date, modifiedAt: date))
        }
    }
}
