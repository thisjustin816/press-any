import EmulatorDomain

public struct AutoStateRetention: Sendable {
    public let keepCount: Int

    public init(keepCount: Int = 5) {
        self.keepCount = max(1, keepCount)
    }

    public func expiredStates(from states: [SaveState]) -> [SaveState] {
        let autos = states
            .filter { $0.kind == .auto }
            .sorted { lhs, rhs in
                if let leftSequence = lhs.autoSequence, let rightSequence = rhs.autoSequence,
                   leftSequence != rightSequence {
                    return leftSequence > rightSequence
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
        guard autos.count > keepCount else { return [] }
        return Array(autos.dropFirst(keepCount))
    }
}
