import Foundation

public enum BuildSaveCompatibility: String, Codable, CaseIterable, Sendable {
    case sharesSaves
    case doesNotShareSaves
}

/// One symmetric declaration, kept by Build identity even when either Build moves Games.
public struct BuildSaveDeclaration: Codable, Equatable, Hashable, Sendable {
    public let firstBuildID: UUID
    public let secondBuildID: UUID
    public let compatibility: BuildSaveCompatibility

    public init(between first: UUID, and second: UUID, compatibility: BuildSaveCompatibility) {
        let ordered = [first, second].sorted { $0.uuidString < $1.uuidString }
        firstBuildID = ordered[0]
        secondBuildID = ordered[1]
        self.compatibility = compatibility
    }

    public func otherBuildID(than buildID: UUID) -> UUID? {
        if buildID == firstBuildID { return secondBuildID }
        if buildID == secondBuildID { return firstBuildID }
        return nil
    }
}
