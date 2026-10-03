import Foundation

public enum GameSystem: String, Codable, Sendable, CaseIterable {
    case gameBoy = "gb"
    case gameBoyColor = "gbc"
}

public enum BuildSourceKind: String, Codable, Sendable {
    case importedImage = "importedROM"
    case patchRecipe
}

public struct CoreDescriptor: Codable, Hashable, Sendable {
    public let identifier: String
    public let version: String

    public init(identifier: String, version: String) {
        self.identifier = identifier
        self.version = version
    }
}

public struct CorePin: Codable, Hashable, Sendable {
    public let descriptor: CoreDescriptor
    public let pinnedAt: Date

    public init(descriptor: CoreDescriptor, pinnedAt: Date) {
        self.descriptor = descriptor
        self.pinnedAt = pinnedAt
    }
}

public struct Build: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var gameID: UUID
    public let system: GameSystem
    public var displayName: String
    public let imageAssetID: UUID
    public let imageSHA256: String
    public let sourceKind: BuildSourceKind
    public let parentBuildID: UUID?
    public var isBase: Bool
    public var region: String?
    public var language: String?
    public var revision: String?
    public var versionString: String?
    public var versionSortKey: String?
    public var preferredSaveProfileID: UUID?
    public var corePin: CorePin?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID,
        gameID: UUID,
        system: GameSystem,
        displayName: String,
        imageAssetID: UUID,
        imageSHA256: String,
        sourceKind: BuildSourceKind,
        parentBuildID: UUID? = nil,
        isBase: Bool = false,
        region: String? = nil,
        language: String? = nil,
        revision: String? = nil,
        versionString: String? = nil,
        versionSortKey: String? = nil,
        preferredSaveProfileID: UUID? = nil,
        corePin: CorePin? = nil,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.gameID = gameID
        self.system = system
        self.displayName = displayName
        self.imageAssetID = imageAssetID
        self.imageSHA256 = imageSHA256
        self.sourceKind = sourceKind
        self.parentBuildID = parentBuildID
        self.isBase = isBase
        self.region = region
        self.language = language
        self.revision = revision
        self.versionString = versionString
        self.versionSortKey = versionSortKey
        self.preferredSaveProfileID = preferredSaveProfileID
        self.corePin = corePin
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
