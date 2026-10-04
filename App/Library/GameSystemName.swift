import EmulatorDomain

extension GameSystem {
    var displayName: String {
        switch self {
        case .gameBoy: "Game Boy"
        case .gameBoyColor: "Game Boy Color"
        }
    }
}
