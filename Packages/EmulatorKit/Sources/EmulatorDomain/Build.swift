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
    /// The image's SHA-1, which No-Intro's data is keyed by. SHA-256 stays the image's identity.
    /// Nil until it is computed: at import for imported images, and once at launch for images
    /// imported before it was kept. Patched Builds leave it nil.
    public var imageSHA1: String?
    public let sourceKind: BuildSourceKind
    public let parentBuildID: UUID?
    public var isBase: Bool
    public var region: String?
    public var language: String?
    public var revision: String?
    public var versionString: String?
    public var versionSortKey: String?
    public var baseTitle: String?
    public var hackTitle: String?
    public var author: String?
    public var translation: String?
    public var status: String?
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
        imageSHA1: String? = nil,
        sourceKind: BuildSourceKind,
        parentBuildID: UUID? = nil,
        isBase: Bool = false,
        region: String? = nil,
        language: String? = nil,
        revision: String? = nil,
        versionString: String? = nil,
        versionSortKey: String? = nil,
        baseTitle: String? = nil,
        hackTitle: String? = nil,
        author: String? = nil,
        translation: String? = nil,
        status: String? = nil,
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
        self.imageSHA1 = imageSHA1?.lowercased()
        self.sourceKind = sourceKind
        self.parentBuildID = parentBuildID
        self.isBase = isBase
        self.region = region
        self.language = language
        self.revision = revision
        self.versionString = versionString
        self.versionSortKey = versionSortKey
        self.baseTitle = baseTitle
        self.hackTitle = hackTitle
        self.author = author
        self.translation = translation
        self.status = status
        self.preferredSaveProfileID = preferredSaveProfileID
        self.corePin = corePin
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
