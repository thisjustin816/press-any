import Foundation

public enum SaveStateKind: String, Codable, Sendable {
    case manual
    case quick
    case slot
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
    public var kind: SaveStateKind
    public var slot: Int?
    public var isPinned: Bool
    public let isTimed: Bool
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
        slot: Int? = nil,
        isPinned: Bool = false,
        isTimed: Bool = false,
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
        self.slot = slot
        self.isPinned = isPinned
        self.isTimed = isTimed
        self.autoSequence = autoSequence
        self.label = label
        self.playtimeSeconds = playtimeSeconds
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, buildID, saveProfileID, core, stateSerializationVersion, stateAssetID, screenshotAssetID
        case kind, slot, isPinned, isTimed, autoSequence, label, playtimeSeconds, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            buildID: try values.decode(UUID.self, forKey: .buildID),
            saveProfileID: try values.decode(UUID.self, forKey: .saveProfileID),
            core: try values.decode(CoreDescriptor.self, forKey: .core),
            stateSerializationVersion: try values.decode(String.self, forKey: .stateSerializationVersion),
            stateAssetID: try values.decode(UUID.self, forKey: .stateAssetID),
            screenshotAssetID: try values.decodeIfPresent(UUID.self, forKey: .screenshotAssetID),
            kind: try values.decode(SaveStateKind.self, forKey: .kind),
            slot: try values.decodeIfPresent(Int.self, forKey: .slot),
            isPinned: try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            isTimed: try values.decodeIfPresent(Bool.self, forKey: .isTimed) ?? false,
            autoSequence: try values.decodeIfPresent(Int.self, forKey: .autoSequence),
            label: try values.decodeIfPresent(String.self, forKey: .label),
            playtimeSeconds: try values.decode(Double.self, forKey: .playtimeSeconds),
            createdAt: try values.decode(Date.self, forKey: .createdAt)
        )
    }
}

extension SaveState {
    public var timingNote: String? { isTimed ? "Timed" : nil }

    /// What a state is called without a label.
    public var kindName: String {
        switch kind {
        case .quick: "Quick Save"
        case .slot: slot.map { "Slot \($0)" } ?? "Save State"
        case .auto: "Auto State"
        case .manual, .crashRecovery: "Save State"
        }
    }

    /// Its label, or its kind when it has none.
    public var displayName: String {
        label ?? kindName
    }
}
