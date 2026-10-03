import EmulatorDomain
import Foundation

public protocol SettingsStore: Sendable {
    func valueJSON(key: String, scope: SettingsScope) throws -> String?
    func setValueJSON(_ valueJSON: String, key: String, scope: SettingsScope) throws
    func removeValue(key: String, scope: SettingsScope) throws
}

public extension SettingsStore {
    func set<T: Encodable>(
        _ value: T,
        key: String,
        scope: SettingsScope,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SettingsStoreEncodingError.invalidUTF8
        }
        try setValueJSON(json, key: key, scope: scope)
    }
}

public enum SettingsStoreEncodingError: Error, Equatable {
    case invalidUTF8
}
