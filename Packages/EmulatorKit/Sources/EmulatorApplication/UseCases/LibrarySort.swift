import EmulatorDomain
import Foundation

public enum LibrarySort: String, CaseIterable, Sendable {
    case title
    case recentlyPlayed
    case recentlyAdded
    case recentlyChanged
    case playtime
    case system
    case hackAuthor
    case version
    case manual

    /// `preferredBuilds` supplies Hack Author and Version, `manualPositions` the Manual order.
    public func sorted(
        games: [Game],
        systems: [UUID: GameSystem],
        statistics: [UUID: GameStatistics],
        preferredBuilds: [UUID: Build] = [:],
        manualPositions: [UUID: Int] = [:]
    ) -> [Game] {
        games.sorted { lhs, rhs in
            let left = statistics[lhs.id] ?? GameStatistics(game: lhs)
            let right = statistics[rhs.id] ?? GameStatistics(game: rhs)
            switch self {
            case .title:
                break
            case .recentlyPlayed:
                if left.hasBeenPlayed != right.hasBeenPlayed { return left.hasBeenPlayed }
                if let order = Self.missingLast(left.lastPlayedAt, right.lastPlayedAt, Self.descending) { return order }
            case .recentlyAdded:
                if left.addedAt != right.addedAt { return left.addedAt > right.addedAt }
            case .recentlyChanged:
                if let order = Self.missingLast(left.lastBuildChangeAt, right.lastBuildChangeAt, Self.descending) { return order }
            case .playtime:
                if left.hasBeenPlayed != right.hasBeenPlayed { return left.hasBeenPlayed }
                if left.totalPlaytimeSeconds != right.totalPlaytimeSeconds {
                    return left.totalPlaytimeSeconds > right.totalPlaytimeSeconds
                }
            case .system:
                let leftSystem = systems[lhs.id] ?? .gameBoy
                let rightSystem = systems[rhs.id] ?? .gameBoy
                if leftSystem != rightSystem { return leftSystem == .gameBoy }
            case .hackAuthor:
                let authorOrder = Self.missingLast(
                    Self.hackAuthor(of: preferredBuilds[lhs.id]), Self.hackAuthor(of: preferredBuilds[rhs.id])
                ) { $0.localizedCaseInsensitiveCompare($1) }
                if let authorOrder { return authorOrder }
            case .version:
                // Sort keys compare as text, the way SQLite orders them.
                let versionOrder = Self.missingLast(
                    preferredBuilds[lhs.id]?.versionSortKey, preferredBuilds[rhs.id]?.versionSortKey, Self.descending
                )
                if let versionOrder { return versionOrder }
            case .manual:
                if let order = Self.missingLast(manualPositions[lhs.id], manualPositions[rhs.id], Self.ascending) { return order }
            }
            let titleOrder = lhs.primaryTitle.localizedCaseInsensitiveCompare(rhs.primaryTitle)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// The Build each Game plays and shows its system from: its Preferred Build, or its first live
    /// Build when none is set.
    public static func preferredBuilds(games: [Game], builds: [Build]) -> [UUID: Build] {
        let buildsByGame = Dictionary(grouping: builds, by: \.gameID)
        var result: [UUID: Build] = [:]
        for game in games {
            let builds = buildsByGame[game.id] ?? []
            result[game.id] = builds.first { $0.id == game.preferredBuildID } ?? builds.first
        }
        return result
    }

    /// The whole library's manual order after the player drags the Games they can see into
    /// `rearrangedVisible`. Games hidden by search or Favorites Only keep their places; the visible
    /// ones take the places the visible Games held, in their new order.
    public static func manualOrder(current: [UUID], rearrangedVisible: [UUID]) -> [UUID] {
        let visible = Set(rearrangedVisible)
        var moved = rearrangedVisible.makeIterator()
        return current.map { visible.contains($0) ? moved.next() ?? $0 : $0 }
    }

    /// The author Hack Author sorts by, nil when the Build has none or only spaces.
    public static func hackAuthor(of build: Build?) -> String? {
        let author = build?.author?.trimmingCharacters(in: .whitespacesAndNewlines)
        return author?.isEmpty == false ? author : nil
    }

    /// Nil when the values tie, so title order decides; otherwise whether the left goes first,
    /// with missing values last.
    private static func missingLast<Value>(
        _ left: Value?, _ right: Value?, _ compare: (Value, Value) -> ComparisonResult
    ) -> Bool? {
        switch (left, right) {
        case (nil, nil): return nil
        case (nil, _): return false
        case (_, nil): return true
        case let (left?, right?):
            let order = compare(left, right)
            return order == .orderedSame ? nil : order == .orderedAscending
        }
    }

    private static func ascending<Value: Comparable>(_ left: Value, _ right: Value) -> ComparisonResult {
        left < right ? .orderedAscending : left > right ? .orderedDescending : .orderedSame
    }

    private static func descending<Value: Comparable>(_ left: Value, _ right: Value) -> ComparisonResult {
        ascending(right, left)
    }
}
