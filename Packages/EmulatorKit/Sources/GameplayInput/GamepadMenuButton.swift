public enum GamepadMenuAction: Equatable, Sendable {
    case open
    case closeAndResume
}

public struct GamepadMenuButton: Sendable {
    private var wasPressed = false

    public init() {}

    public mutating func update(isPressed: Bool, menuIsOpen: Bool) -> GamepadMenuAction? {
        defer { wasPressed = isPressed }
        guard isPressed, !wasPressed else { return nil }
        return menuIsOpen ? .closeAndResume : .open
    }
}
