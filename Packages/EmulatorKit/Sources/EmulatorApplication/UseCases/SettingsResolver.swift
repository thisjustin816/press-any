import EmulatorDomain
import Foundation

public struct ResolvedSetting: Equatable, Sendable {
    public let key: String
    public let valueJSON: String
    public let source: SettingsScope

    public init(key: String, valueJSON: String, source: SettingsScope) {
        self.key = key
        self.valueJSON = valueJSON
        self.source = source
    }

    public func decode<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        try decoder.decode(type, from: Data(valueJSON.utf8))
    }
}

public struct SettingsResolver: Sendable {
    private let store: any SettingsStore

    public init(store: any SettingsStore) {
        self.store = store
    }

    public func resolve(
        key: String,
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil
    ) throws -> ResolvedSetting? {
        for scope in Self.precedence(system: system, gameID: gameID, buildID: buildID) {
            if let value = try store.valueJSON(key: key, scope: scope) {
                return ResolvedSetting(key: key, valueJSON: value, source: scope)
            }
        }
        return nil
    }

    public func decode<T: Decodable>(
        _ type: T.Type,
        key: String,
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T? {
        guard let resolved = try resolve(
            key: key,
            system: system,
            gameID: gameID,
            buildID: buildID
        ) else {
            return nil
        }
        return try resolved.decode(type, decoder: decoder)
    }

    public static func precedence(
        system: GameSystem,
        gameID: UUID?,
        buildID: UUID?
    ) -> [SettingsScope] {
        var scopes: [SettingsScope] = []
        if let buildID { scopes.append(.build(buildID)) }
        if let gameID { scopes.append(.game(gameID)) }
        scopes.append(.system(system))
        scopes.append(.app)
        return scopes
    }
}
