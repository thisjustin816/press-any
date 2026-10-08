import Foundation

public enum MetadataField: String, Codable, CaseIterable, Sendable {
    case title
    case displayName
    case region
    case language
    case revision
    case versionString
    case baseTitle
    case hackTitle
    case author
    case translation
    case status

    public func value(in build: Build) -> String? {
        if self == .displayName { return build.displayName }
        return buildMetadataKeyPath.flatMap { build[keyPath: $0] }
    }

    public var buildMetadataKeyPath: WritableKeyPath<Build, String?>? {
        switch self {
        case .title, .displayName: nil
        case .region: \Build.region
        case .language: \Build.language
        case .revision: \Build.revision
        case .versionString: \Build.versionString
        case .baseTitle: \Build.baseTitle
        case .hackTitle: \Build.hackTitle
        case .author: \Build.author
        case .translation: \Build.translation
        case .status: \Build.status
        }
    }
}

public enum MetadataSource: String, Codable, Sendable {
    case noIntro
    case romHeader
    case filename
    case patch
    case player
}

public enum MetadataConfidence: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct MetadataProvenance: Codable, Equatable, Sendable {
    public let field: MetadataField
    public let source: MetadataSource
    public let confidence: MetadataConfidence?
    /// The source's offered value survives player corrections, including clearing a field.
    public let providedValue: String?
    public let recordedAt: Date

    public init(field: MetadataField, source: MetadataSource, confidence: MetadataConfidence? = nil,
                providedValue: String?, recordedAt: Date) {
        self.field = field
        self.source = source
        self.confidence = confidence
        self.providedValue = providedValue
        self.recordedAt = recordedAt
    }

    public func playerOverride(recordedAt: Date) -> MetadataProvenance {
        MetadataProvenance(field: field, source: .player, providedValue: providedValue, recordedAt: recordedAt)
    }
}
