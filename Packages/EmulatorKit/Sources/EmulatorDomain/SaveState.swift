import Foundation

public enum SaveStateKind: String, Codable, Sendable {
    case manual
    case quick
    case auto
    case crashRecovery
}

public struct SaveState: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let buildID: UUID
    public let saveProfileID: UUID
    public let core: CoreDescriptor
    public let stateSerializationVersion: String
    public let stateAssetID: UUID
    public let screenshotAssetID: UUID?
    public let kind: SaveStateKind
    public let autoSequence: Int?
    public var label: String?
    public let playtimeSeconds: Double
    public let createdAt: Date

    public init(
        id: UUID,
        buildID: UUID,
        saveProfileID: UUID,
        core: CoreDescriptor,
        stateSerializationVersion: String,
        stateAssetID: UUID,
        screenshotAssetID: UUID? = nil,
        kind: SaveStateKind,
        autoSequence: Int? = nil,
        label: String? = nil,
        playtimeSeconds: Double,
        createdAt: Date
    ) {
        self.id = id
        self.buildID = buildID
        self.saveProfileID = saveProfileID
        self.core = core
        self.stateSerializationVersion = stateSerializationVersion
        self.stateAssetID = stateAssetID
        self.screenshotAssetID = screenshotAssetID
        self.kind = kind
        self.autoSequence = autoSequence
        self.label = label
        self.playtimeSeconds = playtimeSeconds
        self.createdAt = createdAt
    }
}

extension SaveState {
    /// What a state is called without a label.
    public var kindName: String {
        kind == .auto ? "Auto State" : "Save State"
    }

    /// Its label, or its kind when it has none.
    public var displayName: String {
        label ?? kindName
    }
}
