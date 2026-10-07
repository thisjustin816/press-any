import EmulatorDomain
import Foundation

public enum SessionLaunchAction: Equatable, Sendable {
    case library
    case recover(LaunchContext, SaveState)
    case reopen(LaunchContext)
}

/// A library session's launch context and open flag, stored at app scope.
public struct SessionLaunchHistory: Sendable {
    private static let key = "session.launchMarker"
    private let store: any SettingsStore

    private struct Marker: Codable {
        let gameID: UUID
        let buildID: UUID
        let saveProfileID: UUID
        let isOpen: Bool

        var context: LaunchContext {
            LaunchContext(gameID: gameID, buildID: buildID, saveProfileID: saveProfileID)
        }
    }

    public init(store: any SettingsStore) {
        self.store = store
    }

    public func started(_ context: LaunchContext) throws {
        try write(context, isOpen: true)
    }

    public func backgroundSaved(_ context: LaunchContext) throws {
        try write(context, isOpen: false)
    }

    public func closed() throws {
        try store.removeValue(key: Self.key, scope: .app)
    }

    public func context() throws -> LaunchContext? {
        try marker()?.context
    }

    /// Consumes the reopen marker before core loading so a launch failure cannot repeat automatically.
    public func launchAction(checkpoint: SaveState?) throws -> SessionLaunchAction {
        guard let marker = try marker() else { return .library }
        if !marker.isOpen {
            try closed()
            return .reopen(marker.context)
        }
        guard let checkpoint, checkpoint.kind == .crashRecovery,
              checkpoint.buildID == marker.buildID, checkpoint.saveProfileID == marker.saveProfileID else {
            return .library
        }
        return .recover(marker.context, checkpoint)
    }

    private func marker() throws -> Marker? {
        guard let json = try store.valueJSON(key: Self.key, scope: .app) else { return nil }
        return try JSONDecoder().decode(Marker.self, from: Data(json.utf8))
    }

    private func write(_ context: LaunchContext, isOpen: Bool) throws {
        try store.set(
            Marker(gameID: context.gameID, buildID: context.buildID, saveProfileID: context.saveProfileID, isOpen: isOpen),
            key: Self.key, scope: .app
        )
    }
}
