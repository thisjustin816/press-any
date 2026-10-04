import Foundation

public enum ManagedAssetKind: String, Codable, Sendable {
    case sourceImage = "sourceROM"
    case sourcePatch
    case generatedImage = "generatedROM"
    case persistentSave = "batterySave"
    case saveState
    case stateThumbnail
    case quickPlayImage = "quickPlayROM"
    case artwork
    case variableMap
}

public enum ManagedAssetStorageClass: String, Codable, Sendable {
    case source
    case userData
    case cache
    case temporary
}

public enum IntegrityStatus: String, Codable, Sendable {
    case verified
    case unknown
    case corrupt
}

public struct ManagedAsset: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: ManagedAssetKind
    public let storageClass: ManagedAssetStorageClass
    public let contentSHA256: String
    public let byteLength: Int64
    public let relativePath: String
    public let originalFilename: String?
    public let provenanceJSON: String?
    public var integrityStatus: IntegrityStatus
    public let createdAt: Date

    public init(
        id: UUID,
        kind: ManagedAssetKind,
        storageClass: ManagedAssetStorageClass,
        contentSHA256: String,
        byteLength: Int64,
        relativePath: String,
        originalFilename: String? = nil,
        provenanceJSON: String? = nil,
        integrityStatus: IntegrityStatus = .unknown,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.storageClass = storageClass
        self.contentSHA256 = contentSHA256
        self.byteLength = byteLength
        self.relativePath = relativePath
        self.originalFilename = originalFilename
        self.provenanceJSON = provenanceJSON
        self.integrityStatus = integrityStatus
        self.createdAt = createdAt
    }
}
