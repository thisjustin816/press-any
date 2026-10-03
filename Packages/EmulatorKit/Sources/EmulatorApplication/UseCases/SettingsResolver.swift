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

    /// What an editor for `scope` shows: the override stored at that scope, and the value it
    /// inherits from the scopes below it, which is what Reset to Inherited would leave in effect.
    /// `scope` must be one of the scopes `system`, `gameID` and `buildID` describe.
    public func edit(
        key: String,
        at scope: SettingsScope,
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil
    ) throws -> ScopedSetting {
        let scopes = Self.precedence(system: system, gameID: gameID, buildID: buildID)
        guard let index = scopes.firstIndex(of: scope) else {
            throw SettingsResolverError.scopeOutsideContext(scope)
        }
        var inherited: ResolvedSetting?
        for parent in scopes[(index + 1)...] {
            if let value = try store.valueJSON(key: key, scope: parent) {
                inherited = ResolvedSetting(key: key, valueJSON: value, source: parent)
                break
            }
        }
        return ScopedSetting(
            key: key,
            scope: scope,
            overrideJSON: try store.valueJSON(key: key, scope: scope),
            inherited: inherited
        )
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

public enum SettingsResolverError: Error, Equatable {
    case scopeOutsideContext(SettingsScope)
}

public struct ScopedSetting: Equatable, Sendable {
    public let key: String
    public let scope: SettingsScope
    /// The value stored at `scope`, or nil when the scope inherits.
    public let overrideJSON: String?
    /// The nearest value below `scope`, or nil when only the built-in default applies.
    public let inherited: ResolvedSetting?

    public init(key: String, scope: SettingsScope, overrideJSON: String?, inherited: ResolvedSetting?) {
        self.key = key
        self.scope = scope
        self.overrideJSON = overrideJSON
        self.inherited = inherited
    }
}
