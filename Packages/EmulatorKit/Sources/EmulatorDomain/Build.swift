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
    public var baseGameReference: BaseGameReference?
    public var baseTitle: String?
    public var hackTitle: String?
    public var author: String?
    public var translation: String?
    public var status: String?
    public var notes: String
    public var totalPlaytimeSeconds: Double
    public var preferredSaveProfileID: UUID?
    public var corePin: CorePin?
    /// The Build's Cheats On switch, which turns all of its cheats on or off at once.
    public var cheatsEnabled: Bool
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
        baseGameReference: BaseGameReference? = nil,
        baseTitle: String? = nil,
        hackTitle: String? = nil,
        author: String? = nil,
        translation: String? = nil,
        status: String? = nil,
        notes: String = "",
        totalPlaytimeSeconds: Double = 0,
        preferredSaveProfileID: UUID? = nil,
        corePin: CorePin? = nil,
        cheatsEnabled: Bool = true,
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
        self.baseGameReference = baseGameReference
        self.baseTitle = baseTitle
        self.hackTitle = hackTitle
        self.author = author
        self.translation = translation
        self.status = status
        self.notes = notes
        self.totalPlaytimeSeconds = totalPlaytimeSeconds
        self.preferredSaveProfileID = preferredSaveProfileID
        self.corePin = corePin
        self.cheatsEnabled = cheatsEnabled
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            gameID: try values.decode(UUID.self, forKey: .gameID),
            system: try values.decode(GameSystem.self, forKey: .system),
            displayName: try values.decode(String.self, forKey: .displayName),
            imageAssetID: try values.decode(UUID.self, forKey: .imageAssetID),
            imageSHA256: try values.decode(String.self, forKey: .imageSHA256),
            imageSHA1: try values.decodeIfPresent(String.self, forKey: .imageSHA1),
            sourceKind: try values.decode(BuildSourceKind.self, forKey: .sourceKind),
            parentBuildID: try values.decodeIfPresent(UUID.self, forKey: .parentBuildID),
            isBase: try values.decode(Bool.self, forKey: .isBase),
            region: try values.decodeIfPresent(String.self, forKey: .region),
            language: try values.decodeIfPresent(String.self, forKey: .language),
            revision: try values.decodeIfPresent(String.self, forKey: .revision),
            versionString: try values.decodeIfPresent(String.self, forKey: .versionString),
            versionSortKey: try values.decodeIfPresent(String.self, forKey: .versionSortKey),
            baseGameReference: try values.decodeIfPresent(BaseGameReference.self, forKey: .baseGameReference),
            baseTitle: try values.decodeIfPresent(String.self, forKey: .baseTitle),
            hackTitle: try values.decodeIfPresent(String.self, forKey: .hackTitle),
            author: try values.decodeIfPresent(String.self, forKey: .author),
            translation: try values.decodeIfPresent(String.self, forKey: .translation),
            status: try values.decodeIfPresent(String.self, forKey: .status),
            notes: try values.decodeIfPresent(String.self, forKey: .notes) ?? "",
            totalPlaytimeSeconds: try values.decodeIfPresent(Double.self, forKey: .totalPlaytimeSeconds) ?? 0,
            preferredSaveProfileID: try values.decodeIfPresent(UUID.self, forKey: .preferredSaveProfileID),
            corePin: try values.decodeIfPresent(CorePin.self, forKey: .corePin),
            cheatsEnabled: try values.decodeIfPresent(Bool.self, forKey: .cheatsEnabled) ?? true,
            createdAt: try values.decode(Date.self, forKey: .createdAt),
            modifiedAt: try values.decode(Date.self, forKey: .modifiedAt)
        )
    }
}
