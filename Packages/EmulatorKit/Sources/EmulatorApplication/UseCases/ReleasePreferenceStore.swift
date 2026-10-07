import EmulatorDomain
import Foundation

public struct ReleasePreferenceStore: Sendable {
    public static let key = "releasePreference"
    private let store: any SettingsStore

    public init(store: any SettingsStore) { self.store = store }

    public func load() throws -> ReleasePreference {
        guard let json = try store.valueJSON(key: Self.key, scope: .app) else { return ReleasePreference() }
        return try JSONDecoder().decode(ReleasePreference.self, from: Data(json.utf8))
    }

    public func save(_ value: ReleasePreference) throws {
        try store.set(value, key: Self.key, scope: .app)
    }
}
