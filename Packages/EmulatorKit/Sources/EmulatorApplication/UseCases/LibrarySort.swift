import EmulatorDomain
import Foundation

public enum LibrarySort: String, CaseIterable, Sendable {
    case title
    case recentlyPlayed
    case recentlyAdded
    case playtime
    case system

    public func sorted(games: [Game], systems: [UUID: GameSystem], statistics: [UUID: GameStatistics]) -> [Game] {
        games.sorted { lhs, rhs in
            let left = statistics[lhs.id] ?? GameStatistics(game: lhs)
            let right = statistics[rhs.id] ?? GameStatistics(game: rhs)
            switch self {
            case .title:
                break
            case .recentlyPlayed:
                if left.hasBeenPlayed != right.hasBeenPlayed { return left.hasBeenPlayed }
                if left.lastPlayedAt != right.lastPlayedAt {
                    guard let leftDate = left.lastPlayedAt else { return false }
                    guard let rightDate = right.lastPlayedAt else { return true }
                    return leftDate > rightDate
                }
            case .recentlyAdded:
                if left.addedAt != right.addedAt { return left.addedAt > right.addedAt }
            case .playtime:
                if left.hasBeenPlayed != right.hasBeenPlayed { return left.hasBeenPlayed }
                if left.totalPlaytimeSeconds != right.totalPlaytimeSeconds {
                    return left.totalPlaytimeSeconds > right.totalPlaytimeSeconds
                }
            case .system:
                let leftSystem = systems[lhs.id] ?? .gameBoy
                let rightSystem = systems[rhs.id] ?? .gameBoy
                if leftSystem != rightSystem { return leftSystem == .gameBoy }
            }
            let titleOrder = lhs.primaryTitle.localizedCaseInsensitiveCompare(rhs.primaryTitle)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
