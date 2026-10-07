import EmulatorDomain

extension BuildSaveCompatibility {
    var displayName: String {
        switch self {
        case .sharesSaves: "Shares Saves"
        case .doesNotShareSaves: "Doesn’t Share Saves"
        }
    }
}
