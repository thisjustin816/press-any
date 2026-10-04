import EmulatorDomain

extension SaveProfile {
    /// The name with its badge in front, for lists and menus.
    var title: String {
        badge.map { "\($0) \(displayName)" } ?? displayName
    }
}
