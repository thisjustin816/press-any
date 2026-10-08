import Foundation

enum PlayStatisticsDisplay {
    static func lastPlayed(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func played(_ date: Date?, hasBeenPlayed: Bool = false) -> String {
        guard date != nil else { return hasBeenPlayed ? "Last Played Unknown" : "Never Played" }
        return "Played \(lastPlayed(date))"
    }
}
