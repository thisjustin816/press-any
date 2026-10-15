import Foundation

public struct AutomaticArtworkSetting: Sendable {
    public static let key = "automaticArtwork"
    private let store: any SettingsStore

    public init(store: any SettingsStore) { self.store = store }

    public func load() throws -> Bool {
        guard let json = try store.valueJSON(key: Self.key, scope: .app) else { return true }
        return try JSONDecoder().decode(Bool.self, from: Data(json.utf8))
    }

    public func save(_ enabled: Bool) throws {
        try store.set(enabled, key: Self.key, scope: .app)
    }
}
